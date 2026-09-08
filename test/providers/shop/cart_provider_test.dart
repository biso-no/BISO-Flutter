import 'package:biso/data/models/product_variation.dart';
import 'package:biso/data/models/webshop_product_model.dart';
import 'package:biso/data/services/shop_api_client.dart';
import 'package:biso/providers/shop/cart_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A stand-in for the shop API that records what the cart asked it to hold.
///
/// Reservations are the one place the cart talks to the server while the buyer
/// is still shopping, so these tests are about what it asks for and how it
/// reacts to being told "you can have fewer than that".
class _FakeShopApi extends ShopApiClient {
  /// What the server says it actually held. `null` means "as much as asked".
  int? heldQuantity;

  /// Thrown from the next [reserve] call, when set.
  ShopApiException? failure;

  final List<({String productId, int quantity})> reserved = [];
  final List<String?> released = [];

  @override
  Future<int> reserve({
    required String productId,
    required int quantity,
    Map<String, String>? customFields,
    Map<String, String>? customFieldLabels,
  }) async {
    if (failure != null) throw failure!;
    reserved.add((productId: productId, quantity: quantity));
    return heldQuantity ?? quantity;
  }

  @override
  Future<void> releaseReservation({String? productId}) async {
    released.add(productId);
  }
}

const _hoodie = WebshopProduct(
  id: 'prod-1',
  images: [],
  slug: 'hoodie',
  title: 'BISO Hoodie',
  regularPrice: 100,
  stock: 10,
);

const _small = ProductVariation(id: 'var-s', name: 'Small', regularPrice: 100);
const _large = ProductVariation(id: 'var-l', name: 'Large', regularPrice: 150);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeShopApi api;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    api = _FakeShopApi();
  });

  Future<CartNotifier> buildCart({String? userId = 'buyer-1'}) async {
    final cart = CartNotifier(api, userId: userId);
    // The persisted cart is read back asynchronously from the constructor.
    await pumpEventQueue();
    return cart;
  }

  group('composition', () {
    test('merges a repeat add of the same configuration', () async {
      final cart = await buildCart();

      await cart.addProduct(product: _hoodie);
      await cart.addProduct(product: _hoodie);

      expect(cart.state.items, hasLength(1));
      expect(cart.state.items.single.quantity, 2);
      expect(cart.state.itemCount, 2);
    });

    test('keeps two variations of one product as separate lines', () async {
      final cart = await buildCart();

      await cart.addProduct(product: _hoodie, variation: _small);
      await cart.addProduct(product: _hoodie, variation: _large);

      expect(cart.state.items, hasLength(2));
      expect(cart.state.itemCount, 2);
      expect(cart.state.subtotal, 250);
    });

    test('keeps two different sets of answers as separate lines', () async {
      final cart = await buildCart();

      await cart.addProduct(
        product: _hoodie,
        customFields: const {'name': 'Kari'},
      );
      await cart.addProduct(
        product: _hoodie,
        customFields: const {'name': 'Ola'},
      );

      expect(cart.state.items, hasLength(2));
    });

    test('removing the last of a line drops it', () async {
      final cart = await buildCart();
      await cart.addProduct(product: _hoodie);

      await cart.setQuantity(cart.state.items.single.lineId, 0);

      expect(cart.state.items, isEmpty);
    });

    test('clearing empties the cart and releases every hold', () async {
      final cart = await buildCart();
      await cart.addProduct(product: _hoodie);

      await cart.clear();

      expect(cart.state.items, isEmpty);
      expect(api.released, contains(null));
    });

    test('a paid checkout clears without re-releasing spent holds', () async {
      final cart = await buildCart();
      await cart.addProduct(product: _hoodie);
      api.released.clear();

      await cart.clear(releaseHolds: false);

      expect(cart.state.items, isEmpty);
      expect(
        api.released,
        isEmpty,
        reason: 'payment already converted the holds into a stock decrement',
      );
    });
  });

  group('stock holds', () {
    test('holds one row per product, summed across its lines', () async {
      final cart = await buildCart();

      await cart.addProduct(product: _hoodie, variation: _small, quantity: 2);
      await cart.addProduct(product: _hoodie, variation: _large, quantity: 3);

      expect(api.reserved.last, (productId: 'prod-1', quantity: 5));
    });

    test('releases the hold when the last line of a product goes', () async {
      final cart = await buildCart();
      await cart.addProduct(product: _hoodie);

      await cart.removeLine(cart.state.items.single.lineId);

      expect(api.released, contains('prod-1'));
    });

    test('scales the cart down to what the server actually held', () async {
      final cart = await buildCart();
      api.heldQuantity = 2;

      await cart.addProduct(product: _hoodie, quantity: 5);

      expect(
        cart.state.items.single.quantity,
        2,
        reason: 'showing 5 would only fail again at checkout',
      );
    });

    test('empties the product from the cart when the stock has gone', () async {
      final cart = await buildCart();
      api.failure = const ShopApiException('Out of stock', statusCode: 409);

      await cart.addProduct(product: _hoodie, quantity: 1);

      expect(cart.state.items, isEmpty);
      expect(cart.state.error, 'Out of stock');
    });

    test('keeps shopping working when the hold cannot be written', () async {
      final cart = await buildCart();
      api.failure = const ShopApiException('boom', statusCode: 500);

      await cart.addProduct(product: _hoodie, quantity: 2);

      expect(
        cart.state.items.single.quantity,
        2,
        reason: 'a hold is a courtesy; the server still enforces stock',
      );
      expect(cart.state.error, isNull);
    });

    test('does not try to hold stock for a signed-out shopper', () async {
      final cart = await buildCart(userId: null);

      await cart.addProduct(product: _hoodie);

      expect(api.reserved, isEmpty);
      expect(cart.state.items, hasLength(1));
    });
  });

  // What `addProduct` reports back. The cart alone cannot answer "did my add
  // land?", because the clamp is applied per product, oldest line first: it can
  // drop the configuration just requested while leaving a different variation
  // of the same product standing.
  group('add result', () {
    test('confirms an add the server held in full', () async {
      final cart = await buildCart();

      final result = await cart.addProduct(product: _hoodie, quantity: 2);

      expect(result.added, 2);
      expect(result.isRejected, isFalse);
      expect(result.isPartial, isFalse);
    });

    test('reports a short add when the server held fewer', () async {
      final cart = await buildCart();
      api.heldQuantity = 2;

      final result = await cart.addProduct(product: _hoodie, quantity: 5);

      expect(result.requested, 5);
      expect(result.added, 2);
      expect(result.isPartial, isTrue);
    });

    test('reports rejection when the clamp kept a different variation', () async {
      final cart = await buildCart();
      await cart.addProduct(product: _hoodie, variation: _small, quantity: 2);
      // Only the two units already held remain, so the size just asked for
      // gets nothing — yet the product is still in the cart.
      api.heldQuantity = 2;

      final result = await cart.addProduct(product: _hoodie, variation: _large);

      expect(result.isRejected, isTrue);
      expect(
        cart.state.items.single.variationId,
        'var-s',
        reason: 'the other size survived, which is why the cart cannot be '
            'used to judge whether this add landed',
      );
    });

    test('reports rejection when a repeat add was clamped back', () async {
      final cart = await buildCart();
      await cart.addProduct(product: _hoodie, quantity: 2);
      api.heldQuantity = 2;

      final result = await cart.addProduct(product: _hoodie, quantity: 3);

      expect(result.isRejected, isTrue);
      expect(cart.state.items.single.quantity, 2);
    });

    test('reports rejection when the stock has gone entirely', () async {
      final cart = await buildCart();
      api.failure = const ShopApiException('Out of stock', statusCode: 409);

      final result = await cart.addProduct(product: _hoodie);

      expect(result.isRejected, isTrue);
      expect(cart.state.items, isEmpty);
    });
  });

  group('persistence', () {
    test('restores the same buyer cart on the next launch', () async {
      final first = await buildCart();
      await first.addProduct(product: _hoodie, quantity: 2);

      final second = await buildCart();

      expect(second.state.items, hasLength(1));
      expect(second.state.items.single.quantity, 2);
      expect(second.state.isLoading, isFalse);
    });

    test('does not hand one account another account cart', () async {
      final first = await buildCart();
      await first.addProduct(product: _hoodie);

      final other = await buildCart(userId: 'buyer-2');

      expect(other.state.items, isEmpty);
    });

    test('drops the cart when the buyer signs out', () async {
      final cart = await buildCart();
      await cart.addProduct(product: _hoodie);

      await cart.handleUserChanged(null);

      expect(cart.state.items, isEmpty);
    });

    test('carries a guest cart into the account that signs in', () async {
      // Browsing and filling a cart is open to anyone, but paying is not — so
      // the cart must survive the sign-in that checkout forces, or it empties
      // at the moment the buyer is most committed.
      final guest = await buildCart(userId: null);
      await guest.addProduct(product: _hoodie, quantity: 2);

      await guest.handleUserChanged('buyer-1');

      expect(guest.state.items, hasLength(1));
      expect(guest.state.items.single.quantity, 2);
    });

    test('holds the stock a guest cart could not reserve, once claimed', () async {
      final guest = await buildCart(userId: null);
      await guest.addProduct(product: _hoodie, quantity: 2);
      expect(api.reserved, isEmpty, reason: 'nobody to reserve for yet');

      await guest.handleUserChanged('buyer-1');

      expect(api.reserved, contains((productId: 'prod-1', quantity: 2)));
    });

    test('a claimed guest cart survives the next launch', () async {
      final guest = await buildCart(userId: null);
      await guest.addProduct(product: _hoodie);
      await guest.handleUserChanged('buyer-1');

      final relaunched = await buildCart(userId: 'buyer-1');

      expect(
        relaunched.state.items,
        hasLength(1),
        reason: 'claiming must re-stamp the stored owner, not just the state',
      );
    });

    test('still refuses a cart belonging to a different account', () async {
      final first = await buildCart();
      await first.addProduct(product: _hoodie);

      final other = await buildCart(userId: 'buyer-2');

      expect(other.state.items, isEmpty);
    });
  });
}
