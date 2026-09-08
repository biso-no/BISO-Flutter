import 'dart:convert';

import 'package:biso/data/models/cart_item.dart';
import 'package:biso/data/models/shop_order.dart';
import 'package:biso/data/models/webshop_product_model.dart';
import 'package:biso/data/services/shop_api_client.dart';
import 'package:biso/providers/shop/cart_provider.dart';
import 'package:biso/providers/shop/checkout_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers with one fixed order and records that it was asked.
class _FakeShopApi extends ShopApiClient {
  _FakeShopApi(this.status);

  final ShopOrderStatus status;
  final List<String> fetched = [];

  @override
  Future<ShopOrder> fetchOrder(String orderId) async {
    fetched.add(orderId);
    return ShopOrder(
      id: orderId,
      status: status,
      currency: 'NOK',
      subtotal: 100,
      discountTotal: 0,
      total: 100,
      membershipApplied: false,
      memberDiscountPercent: 0,
      items: const [],
    );
  }

  @override
  Future<void> releaseReservation({String? productId}) async {}
}

const _hoodie = WebshopProduct(
  id: 'prod-1',
  images: [],
  slug: 'hoodie',
  title: 'BISO Hoodie',
  regularPrice: 100,
  stock: 10,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A device that was evicted mid-payment: a cart, and a marker naming the
  /// order the buyer went off to pay for.
  ///
  /// [extraCartLines] are lines the buyer added *after* starting the order, so
  /// they are in the cart but not in the marker — the case that separates
  /// giving up the paid lines from emptying the cart.
  void seedInterruptedCheckout({
    Duration age = Duration.zero,
    List<CartItem> extraCartLines = const <CartItem>[],
    bool markerCarriesLines = true,
  }) {
    final paid = CartItem.fromProduct(product: _hoodie, quantity: 2);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'shop_cart_v1': jsonEncode(
        [paid, ...extraCartLines].map((item) => item.toJson()).toList(),
      ),
      'shop_cart_v1_user': 'buyer-1',
      'shop_pending_order_id': 'order-1',
      'shop_pending_order_started_at': DateTime.now()
          .subtract(age)
          .millisecondsSinceEpoch,
      if (markerCarriesLines)
        'shop_pending_order_lines': jsonEncode({paid.lineId: paid.quantity}),
    });
  }

  ProviderContainer buildContainer(ShopApiClient api) {
    final container = ProviderContainer(
      overrides: [
        shopApiClientProvider.overrideWithValue(api),
        // Pin the buyer rather than standing up the authentication stack.
        cartUserIdProvider.overrideWithValue('buyer-1'),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Builds the controller the way a launch does, then lets both it and the
  /// cart finish their asynchronous restores.
  Future<void> launch(ProviderContainer container) async {
    container.read(checkoutControllerProvider.notifier);
    await pumpEventQueue();
    await container.read(cartProvider.notifier).ready;
  }

  // A cold launch is not a resume: `AppLifecycleListener` reports *changes* to
  // the lifecycle state, and the app is already resumed by the time the
  // controller exists. So construction has to do this work itself, or an order
  // paid while the app was evicted stays unresolved.
  group('recovering a checkout the app was evicted during', () {
    test('verifies the pending order on construction alone', () async {
      seedInterruptedCheckout();
      final api = _FakeShopApi(ShopOrderStatus.paid);
      final container = buildContainer(api);

      await launch(container);

      expect(api.fetched, ['order-1']);
    });

    test('clears the cart the payment already spent', () async {
      seedInterruptedCheckout();
      final container = buildContainer(_FakeShopApi(ShopOrderStatus.paid));

      await launch(container);

      expect(container.read(cartProvider).items, isEmpty);
    });

    test('keeps lines added after the order was placed', () async {
      // The buyer left the pending order, carried on shopping, and only then
      // did the payment resolve. The hoodie was bought; the tote was not.
      const tote = WebshopProduct(
        id: 'prod-2',
        images: [],
        slug: 'tote',
        title: 'BISO Tote',
        regularPrice: 50,
        stock: 10,
      );
      seedInterruptedCheckout(
        extraCartLines: [CartItem.fromProduct(product: tote)],
      );
      final container = buildContainer(_FakeShopApi(ShopOrderStatus.paid));

      await launch(container);

      final items = container.read(cartProvider).items;
      expect(items, hasLength(1));
      expect(items.single.productId, 'prod-2');
    });

    test('clears everything when the marker predates line tracking', () async {
      seedInterruptedCheckout(markerCarriesLines: false);
      final container = buildContainer(_FakeShopApi(ShopOrderStatus.paid));

      await launch(container);

      expect(
        container.read(cartProvider).items,
        isEmpty,
        reason: 'without a record of what was bought, the old behaviour is '
            'the safe one',
      );
    });

    test('forgets the order once it is resolved', () async {
      seedInterruptedCheckout();
      final container = buildContainer(_FakeShopApi(ShopOrderStatus.paid));

      await launch(container);
      final controller = container.read(checkoutControllerProvider.notifier);

      expect(controller.pending, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('shop_pending_order_id'), isNull);
    });

    test('keeps the cart when the payment did not go through', () async {
      seedInterruptedCheckout();
      final container = buildContainer(_FakeShopApi(ShopOrderStatus.cancelled));

      await launch(container);

      expect(
        container.read(cartProvider).items,
        hasLength(1),
        reason: 'the buyer very likely wants to try another payment method',
      );
    });

    test('does not chase a marker old enough to be abandoned', () async {
      seedInterruptedCheckout(age: const Duration(hours: 3));
      final api = _FakeShopApi(ShopOrderStatus.paid);
      final container = buildContainer(api);

      await launch(container);

      expect(api.fetched, isEmpty);
      expect(container.read(cartProvider).items, hasLength(1));
    });

    test('does nothing when no payment was in flight', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final api = _FakeShopApi(ShopOrderStatus.paid);
      final container = buildContainer(api);

      await launch(container);

      expect(api.fetched, isEmpty);
    });
  });
}
