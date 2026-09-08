import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/print_migration.dart';
import '../../data/models/checkout_quote.dart';
import '../../data/models/payment_provider.dart';
import '../../data/models/shop_order.dart';
import '../../data/services/order_service.dart';
import '../../data/services/shop_api_client.dart';
import 'cart_provider.dart';

/// Which payment providers the shop may offer right now.
///
/// Both switches that gate a provider live server-side — the admin app's kill
/// switch and whether credentials are configured — and the second is not
/// readable from the app at all, so this asks rather than guesses. On failure
/// it surfaces the error rather than falling back to a guess: offering a
/// provider the server would refuse sends the buyer to a dead end.
final paymentProvidersProvider =
    FutureProvider.autoDispose<List<PaymentProviderAvailability>>((ref) async {
      final api = ref.watch(shopApiClientProvider);
      return api.fetchProviders();
    });

/// Just the providers that are actually offerable, in display order.
final availablePaymentProvidersProvider =
    Provider.autoDispose<AsyncValue<List<PaymentProvider>>>((ref) {
      return ref
          .watch(paymentProvidersProvider)
          .whenData(
            (providers) => providers
                .where((provider) => provider.available)
                .map((provider) => provider.provider)
                .toList(growable: false),
          );
    });

/// The server's price for the current cart.
///
/// Recomputed whenever the cart changes, because the answer depends on live
/// stock, purchase limits and the buyer's membership — none of which the app
/// can evaluate. A conflict (409) here is the cart telling the buyer something
/// is no longer available *before* they commit to paying.
final checkoutQuoteProvider = FutureProvider.autoDispose<CheckoutQuote>((
  ref,
) async {
  // Narrowed to the lines themselves, so surfacing a cart error (which leaves
  // the lines untouched) does not send the buyer back to a loading spinner.
  final items = ref.watch(cartProvider.select((state) => state.items));
  if (items.isEmpty) {
    throw const ShopApiException('Your cart is empty.');
  }
  return ref.watch(shopApiClientProvider).quote(items);
});

/// A payment the buyer has been sent off to complete.
///
/// Persisted because the buyer leaves the app entirely — into Vipps, or into a
/// browser — and the app may be evicted while they are gone. On the way back,
/// this is what tells the app which order to ask about.
class PendingCheckout {
  final String orderId;
  final DateTime startedAt;

  const PendingCheckout({required this.orderId, required this.startedAt});

  /// Payment sessions do not stay payable forever, and a marker older than
  /// this is far more likely to be an abandoned attempt than one in flight.
  static const Duration maxAge = Duration(hours: 2);

  bool get isStale => DateTime.now().difference(startedAt) > maxAge;
}

/// Drives a checkout attempt and follows it home.
class CheckoutController extends StateNotifier<AsyncValue<void>> {
  CheckoutController(this._ref) : super(const AsyncValue.data(null)) {
    // The buyer completes payment in another app. Coming back to the
    // foreground is the earliest reliable moment to find out how it went —
    // the deep link from the return route is faster but not guaranteed, since
    // a browser may decline to hand a custom scheme back to the app.
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(resolvePendingCheckout()),
    );
    unawaited(_restorePending());
  }

  final Ref _ref;
  late final AppLifecycleListener _lifecycle;

  static const String _pendingOrderKey = 'shop_pending_order_id';
  static const String _pendingStartedKey = 'shop_pending_order_started_at';

  PendingCheckout? _pending;

  PendingCheckout? get pending => _pending;

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _restorePending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final orderId = prefs.getString(_pendingOrderKey);
      final startedAt = prefs.getInt(_pendingStartedKey);
      if (orderId == null || orderId.isEmpty || startedAt == null) return;
      _pending = PendingCheckout(
        orderId: orderId,
        startedAt: DateTime.fromMillisecondsSinceEpoch(startedAt),
      );
      if (_pending!.isStale) {
        await _clearPending();
      }
    } catch (error) {
      logPrint('💳 Failed to restore pending checkout: $error');
    }
  }

  Future<void> _rememberPending(String orderId) async {
    _pending = PendingCheckout(orderId: orderId, startedAt: DateTime.now());
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingOrderKey, orderId);
      await prefs.setInt(
        _pendingStartedKey,
        _pending!.startedAt.millisecondsSinceEpoch,
      );
    } catch (error) {
      logPrint('💳 Failed to persist pending checkout: $error');
    }
  }

  Future<void> _clearPending() async {
    _pending = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingOrderKey);
      await prefs.remove(_pendingStartedKey);
    } catch (error) {
      logPrint('💳 Failed to clear pending checkout: $error');
    }
  }

  /// Creates the order and the payment session.
  ///
  /// [total] must come from a [checkoutQuoteProvider] result for the same cart:
  /// the server recomputes it and refuses the request if the two disagree,
  /// which is exactly the guard that keeps a client from setting its own price.
  Future<StartedCheckout> start({
    required PaymentProvider provider,
    required double subtotal,
    required double total,
    required String email,
    String? firstName,
    String? lastName,
    String? phone,
  }) async {
    state = const AsyncValue.loading();
    try {
      final items = _ref.read(cartProvider).items;
      final started = await _ref
          .read(shopApiClientProvider)
          .startCheckout(
            provider: provider,
            items: items,
            subtotal: subtotal,
            total: total,
            email: email,
            firstName: firstName,
            lastName: lastName,
            phone: phone,
          );
      await _rememberPending(started.orderId);
      state = const AsyncValue.data(null);
      return started;
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }

  /// Asks the server how a payment went, settling the order if it succeeded.
  ///
  /// The response is authoritative: it reconciles with Vipps or Stripe before
  /// answering, so a "paid" here is not a guess about a webhook that may not
  /// have landed yet.
  Future<ShopOrder> verifyOrder(String orderId) async {
    final order = await _ref.read(shopApiClientProvider).fetchOrder(orderId);
    await _applyOutcome(order);
    return order;
  }

  /// Checks on a payment the buyer walked away from, if there is one.
  ///
  /// Silent by design — it runs on every foreground — so a network failure
  /// leaves the marker in place to be retried rather than surfacing an error
  /// over whatever the buyer is actually doing.
  Future<ShopOrder?> resolvePendingCheckout() async {
    final pending = _pending;
    if (pending == null) return null;
    if (pending.isStale) {
      await _clearPending();
      return null;
    }

    try {
      final order = await _ref
          .read(shopApiClientProvider)
          .fetchOrder(pending.orderId);
      await _applyOutcome(order);
      return order;
    } catch (error) {
      logPrint('💳 Could not resolve pending checkout: $error');
      return null;
    }
  }

  /// A paid order means the cart is spent: the server has already turned the
  /// stock holds into a decrement and deleted the reservation rows, so the
  /// cart is cleared without asking it to release holds that are gone.
  ///
  /// A cancelled or failed order also ends the attempt, but the cart is left
  /// alone — the buyer very likely wants to try again with a different method.
  Future<void> _applyOutcome(ShopOrder order) async {
    if (order.status.isSuccessful) {
      await _ref.read(cartProvider.notifier).clear(releaseHolds: false);
      await _clearPending();
      return;
    }
    if (order.status.isFailure) {
      await _clearPending();
    }
  }
}

final checkoutControllerProvider =
    StateNotifierProvider<CheckoutController, AsyncValue<void>>(
      CheckoutController.new,
    );

/// One order, as the confirmation screen renders it while verification runs.
///
/// Reads the Appwrite row directly — order rows carry a per-buyer read grant —
/// so the screen has something to show immediately instead of a spinner.
final orderSnapshotProvider = FutureProvider.autoDispose
    .family<ShopOrder?, String>((ref, orderId) async {
      return OrderService().getOrder(orderId);
    });

/// The buyer's order history.
final myOrdersProvider = FutureProvider.autoDispose<List<ShopOrder>>((
  ref,
) async {
  return OrderService().listMyOrders();
});
