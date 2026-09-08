import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/print_migration.dart';
import '../../data/models/cart_item.dart';
import '../../data/models/product_custom_field.dart';
import '../../data/models/product_variation.dart';
import '../../data/models/webshop_product_model.dart';
import '../../data/services/shop_api_client.dart';
import '../auth/auth_provider.dart';

/// The cart, as the app holds it.
///
/// The app owns the composition of the cart — which product, which variation,
/// which answers — because `cart_reservations` cannot express a variation (it
/// is keyed per product) and the buyer must be able to shop offline. Stock
/// holds are mirrored to that table separately, best effort; see
/// [CartNotifier._syncReservation].
class CartState {
  final List<CartItem> items;

  /// True until the persisted cart has been read back on launch, so the badge
  /// and cart screen do not flash "empty" first.
  final bool isLoading;

  /// The most recent thing that went wrong, for the UI to surface once.
  final String? error;

  const CartState({
    this.items = const <CartItem>[],
    this.isLoading = true,
    this.error,
  });

  bool get isEmpty => items.isEmpty;

  int get itemCount => items.fold<int>(0, (sum, item) => sum + item.quantity);

  /// Indicative total, for the cart screen. The checkout screen shows the
  /// server's quote instead, which is the amount actually charged.
  double get subtotal =>
      items.fold<double>(0, (sum, item) => sum + item.lineTotal);

  CartState copyWith({
    List<CartItem>? items,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return CartState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// What actually ended up in the cart after a [CartNotifier.addProduct] call.
///
/// The stock hold is written as part of the add, and when the server can hold
/// less than was asked for the cart is corrected to match rather than throwing.
/// That correction is applied per *product*, oldest line first, so it can shrink
/// the configuration just requested — or drop it entirely while leaving another
/// variation of the same product untouched. Reporting the outcome explicitly is
/// the only way a caller can tell "added" from "something of this product is in
/// the cart".
class CartAddResult {
  /// The configuration the caller asked for: product, variation and answers.
  final String lineId;

  /// How many units the caller asked to add.
  final int requested;

  /// How many of them survived the stock hold.
  final int added;

  const CartAddResult({
    required this.lineId,
    required this.requested,
    required this.added,
  });

  /// Nothing was added: sold out, or the hold was refused outright.
  bool get isRejected => added <= 0;

  /// Some but not all of the requested units were added.
  bool get isPartial => added > 0 && added < requested;
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier(this._api, {required String? userId})
    : _userId = userId,
      super(const CartState()) {
    _ready = _restore();
  }

  final ShopApiClient _api;

  /// Completes when the persisted cart has been read back.
  ///
  /// The cart is built lazily, so something can mutate it while its very first
  /// restore is still in flight — a checkout resolved at launch clearing the
  /// cart it was just paid for is exactly that case. Without this, the restore
  /// would land afterwards and put the spent lines back.
  Future<void> get ready => _ready;
  late Future<void> _ready;

  /// Whose cart this is. A cart is per-account: signing in as someone else must
  /// not inherit the previous account's lines, and reservations are written
  /// against the signed-in user.
  String? _userId;

  static const String _storageKey = 'shop_cart_v1';
  static const String _storageUserKey = 'shop_cart_v1_user';

  /// Re-reads the persisted cart for the current account.
  ///
  /// Called on construction and whenever the signed-in user changes, so the
  /// cart follows the account rather than the device.
  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedUser = prefs.getString(_storageUserKey);

      // Browsing and filling a cart is deliberately open to anyone; only
      // paying needs an account. So a cart saved with no owner belongs to
      // whoever is now signing in — discarding it would empty the cart at
      // precisely the sign-in step checkout forces on them, which is the one
      // moment they are most committed to buying.
      final claimsGuestCart = storedUser == null && _userId != null;

      if (storedUser != _userId && !claimsGuestCart) {
        // Someone else's cart, or this buyer signing out on a shared device.
        state = const CartState(items: <CartItem>[], isLoading: false);
        return;
      }

      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) {
        state = const CartState(items: <CartItem>[], isLoading: false);
        return;
      }

      final decoded = jsonDecode(raw);
      final items = decoded is List
          ? decoded
                .whereType<Map>()
                .map((e) => CartItem.fromJson(Map<String, dynamic>.from(e)))
                .where((item) => item.productId.isNotEmpty && item.quantity > 0)
                .toList()
          : <CartItem>[];
      state = CartState(items: items, isLoading: false);

      if (claimsGuestCart) {
        // Re-stamp the cart with its new owner, then take out the stock holds
        // that could not be written while there was nobody to write them for.
        // The sync also corrects anything that sold out in the meantime.
        await _persist();
        for (final productId in {
          for (final item in items) item.productId,
        }) {
          await _syncReservation(productId);
        }
      }
    } catch (error) {
      logPrint('🛒 Failed to restore cart: $error');
      state = const CartState(items: <CartItem>[], isLoading: false);
    }
  }

  /// Called when the signed-in account changes.
  Future<void> handleUserChanged(String? userId) async {
    if (_userId == userId) return;
    _userId = userId;
    _ready = _restore();
    await _ready;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(state.items.map((item) => item.toJson()).toList()),
      );
      if (_userId == null) {
        await prefs.remove(_storageUserKey);
      } else {
        await prefs.setString(_storageUserKey, _userId!);
      }
    } catch (error) {
      logPrint('🛒 Failed to persist cart: $error');
    }
  }

  Future<void> _commit(List<CartItem> items) async {
    state = state.copyWith(items: items, isLoading: false, clearError: true);
    await _persist();
  }

  /// Mirrors a product's total quantity into `cart_reservations`.
  ///
  /// Best effort by design: the hold is a courtesy that stops two buyers
  /// racing for the last unit, not the thing that prevents overselling — the
  /// checkout endpoint re-validates availability and the stock decrement on
  /// payment is atomic. So a failure here (offline, signed out, a server
  /// hiccup) must never block shopping.
  ///
  /// The server clamps to live availability and returns what it actually held;
  /// when that is less than asked for, the cart is corrected to match so the
  /// buyer is not shown a quantity that will be refused at checkout.
  Future<void> _syncReservation(String productId) async {
    if (_userId == null) return;

    final lines = state.items
        .where((item) => item.productId == productId)
        .toList(growable: false);

    try {
      if (lines.isEmpty) {
        await _api.releaseReservation(productId: productId);
        return;
      }

      // One reservation row per product, so hold the sum across every line of
      // that product (a hoodie in two sizes is two lines, one hold).
      final requested = lines.fold<int>(0, (sum, item) => sum + item.quantity);
      // The row holds one set of answers; use the first line that has any, the
      // same shape the website writes.
      final withAnswers = lines.firstWhere(
        (item) => item.customFields.isNotEmpty,
        orElse: () => lines.first,
      );

      final held = await _api.reserve(
        productId: productId,
        quantity: requested,
        customFields: withAnswers.customFields.isEmpty
            ? null
            : withAnswers.customFields,
        customFieldLabels: withAnswers.customFieldLabels,
      );

      if (held < requested) {
        await _applyHeldQuantity(productId, held);
      }
    } on ShopApiException catch (error) {
      if (error.isConflict) {
        // The stock went while the buyer was deciding. Correct the cart rather
        // than letting checkout fail later with the same message.
        await _applyHeldQuantity(productId, 0);
        state = state.copyWith(error: error.message);
      } else {
        logPrint('🛒 Reservation sync failed: ${error.message}');
      }
    } catch (error) {
      logPrint('🛒 Reservation sync failed: $error');
    }
  }

  /// Scales this product's lines down to the quantity the server actually
  /// held, dropping lines entirely when nothing is left.
  Future<void> _applyHeldQuantity(String productId, int held) async {
    var remaining = held;
    final next = <CartItem>[];
    for (final item in state.items) {
      if (item.productId != productId) {
        next.add(item);
        continue;
      }
      final allowed = remaining <= 0
          ? 0
          : (item.quantity < remaining ? item.quantity : remaining);
      remaining -= allowed;
      if (allowed > 0) {
        next.add(item.copyWith(quantity: allowed));
      }
    }
    await _commit(next);
  }

  /// Adds a configuration of a product, merging into an existing line when the
  /// same product, variation and answers are already in the cart.
  ///
  /// Returns what actually landed. The add is not the last word: the
  /// reservation sync below can clamp this product's lines to what the server
  /// could hold, and the caller cannot tell from the cart alone — a *different*
  /// configuration of the same product left standing looks exactly like
  /// success.
  Future<CartAddResult> addProduct({
    required WebshopProduct product,
    ProductVariation? variation,
    int quantity = 1,
    Map<String, String> customFields = const <String, String>{},
    List<ProductCustomField> customFieldDefinitions =
        const <ProductCustomField>[],
  }) async {
    await _ready;
    final line = CartItem.fromProduct(
      product: product,
      variation: variation,
      quantity: quantity,
      customFields: customFields,
      customFieldDefinitions: customFieldDefinitions,
    );

    // Measured either side of the sync: the difference is exactly how many of
    // the requested units survived, whether this line was new or merged into
    // one already in the cart.
    final before = _quantityOfLine(line.lineId);

    final items = [...state.items];
    final index = items.indexWhere((item) => item.lineId == line.lineId);
    if (index >= 0) {
      items[index] = items[index].copyWith(
        quantity: items[index].quantity + quantity,
      );
    } else {
      items.add(line);
    }

    await _commit(items);
    await _syncReservation(line.productId);

    final delta = _quantityOfLine(line.lineId) - before;
    return CartAddResult(
      lineId: line.lineId,
      requested: quantity,
      added: delta < 0 ? 0 : (delta > quantity ? quantity : delta),
    );
  }

  int _quantityOfLine(String lineId) {
    for (final item in state.items) {
      if (item.lineId == lineId) return item.quantity;
    }
    return 0;
  }

  Future<void> setQuantity(String lineId, int quantity) async {
    await _ready;
    final index = state.items.indexWhere((item) => item.lineId == lineId);
    if (index < 0) return;

    if (quantity < 1) {
      await removeLine(lineId);
      return;
    }

    final items = [...state.items];
    final productId = items[index].productId;
    items[index] = items[index].copyWith(quantity: quantity);
    await _commit(items);
    await _syncReservation(productId);
  }

  Future<void> removeLine(String lineId) async {
    await _ready;
    final index = state.items.indexWhere((item) => item.lineId == lineId);
    if (index < 0) return;

    final productId = state.items[index].productId;
    final items = [...state.items]..removeAt(index);
    await _commit(items);
    await _syncReservation(productId);
  }

  /// Empties the cart and releases every hold.
  ///
  /// [releaseHolds] is false after a successful payment: the server has already
  /// converted the holds into a stock decrement and deleted the rows, so asking
  /// again is pointless work on a screen the buyer is looking at.
  Future<void> clear({bool releaseHolds = true}) async {
    await _ready;
    await _commit(const <CartItem>[]);
    if (releaseHolds && _userId != null) {
      try {
        await _api.releaseReservation();
      } catch (error) {
        logPrint('🛒 Failed to release reservations: $error');
      }
    }
  }

  void clearError() {
    if (state.error != null) {
      state = state.copyWith(clearError: true);
    }
  }
}

final shopApiClientProvider = Provider<ShopApiClient>((ref) => ShopApiClient());

/// Whose cart this is.
///
/// A one-field view of the auth state rather than a direct dependency on it,
/// so the cart reacts only to the buyer changing (not to every unrelated auth
/// field) and so a widget test can pin an identity without standing up the
/// whole authentication stack.
final cartUserIdProvider = Provider<String?>(
  (ref) => ref.watch(authStateProvider.select((state) => state.user?.id)),
);

final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  final notifier = CartNotifier(
    ref.watch(shopApiClientProvider),
    userId: ref.read(cartUserIdProvider),
  );

  // Reload the cart when the account changes, so a sign-in picks up that
  // buyer's cart and a sign-out does not leave it on a shared device.
  ref.listen<String?>(cartUserIdProvider, (previous, next) {
    if (previous != next) {
      notifier.handleUserChanged(next);
    }
  });

  return notifier;
});

/// Total units in the cart, for the badge.
final cartItemCountProvider = Provider<int>(
  (ref) => ref.watch(cartProvider).itemCount,
);
