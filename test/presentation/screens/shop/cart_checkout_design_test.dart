import 'dart:convert';

import 'package:biso/data/models/cart_item.dart';
import 'package:biso/data/models/checkout_quote.dart';
import 'package:biso/data/models/payment_provider.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/models/webshop_product_model.dart';
import 'package:biso/presentation/screens/shop/cart_screen.dart';
import 'package:biso/presentation/screens/shop/checkout_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/shop/cart_provider.dart';
import 'package:biso/providers/shop/checkout_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/biso_screen_harness.dart';

const _buyerId = 'buyer-1';

const _user = UserModel(id: _buyerId, name: 'Test Buyer', email: 'buyer@bi.no');

/// A signed-in user, mirroring the `_Auth` pattern used by the other design
/// tests (e.g. profile_design_test.dart).
class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth() : super(const AuthState(isAuthenticated: true, user: _user));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

WebshopProduct _product(int index) => WebshopProduct(
  id: 'prod-$index',
  images: const [],
  slug: 'item-$index',
  title: 'Item $index',
  regularPrice: 100.0 + index,
  stock: 20,
);

List<CartItem> _lines(int count) => [
  for (var i = 0; i < count; i++)
    CartItem.fromProduct(product: _product(i), quantity: 1),
];

/// Persists [items] as the cart for [_buyerId], the way a real launch would
/// restore it from disk.
void _seedCart(List<CartItem> items) {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'shop_cart_v1': jsonEncode(items.map((item) => item.toJson()).toList()),
    'shop_cart_v1_user': _buyerId,
  });
}

const _quote = CheckoutQuote(
  currency: 'NOK',
  subtotal: 100,
  discountTotal: 0,
  total: 100,
  membershipApplied: false,
  memberDiscountPercent: 0,
  items: [
    CheckoutQuoteLine(
      productId: 'prod-0',
      name: 'Item 0',
      title: 'Item 0',
      quantity: 1,
      unitPrice: 100,
      lineTotal: 100,
    ),
  ],
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('Cart', () {
    testWidgets('builds on BisoPage in every appearance, empty and with a line', (
      tester,
    ) async {
      await expectBuildsCleanly(
        tester,
        () => const CartScreen(),
        overrides: [cartUserIdProvider.overrideWithValue(null)],
      );

      _seedCart(_lines(1));
      await expectBuildsCleanly(
        tester,
        () => const CartScreen(),
        overrides: [cartUserIdProvider.overrideWithValue(_buyerId)],
      );
    });

    testWidgets(
      'with 12 lines, scrolling to the end leaves the last line clear of '
      'the bottom bar',
      (tester) async {
        final lines = _lines(12);
        _seedCart(lines);
        await pumpBisoScreen(
          tester,
          const CartScreen(),
          overrides: [cartUserIdProvider.overrideWithValue(_buyerId)],
        );
        await tester.pumpAndSettle();

        await tester.fling(
          find.byType(CustomScrollView),
          const Offset(0, -4000),
          3000,
        );
        await tester.pumpAndSettle();

        final lastLine = find.byKey(
          ValueKey('cart-line-${lines.last.lineId}'),
        );
        expect(lastLine, findsOneWidget);
        final lineBottom = tester.getBottomLeft(lastLine).dy;
        final barTop = tester.getTopLeft(find.byType(BisoBottomBar)).dy;
        expect(lineBottom, lessThanOrEqualTo(barTop));
      },
    );
  });

  group('Checkout', () {
    List<Override> overrides({
      required List<PaymentProviderAvailability> providers,
    }) => [
      authStateProvider.overrideWith((_) => _Auth()),
      cartUserIdProvider.overrideWithValue(_buyerId),
      checkoutQuoteProvider.overrideWith((ref) async => _quote),
      paymentProvidersProvider.overrideWith((ref) async => providers),
    ];

    testWidgets('builds on BisoPage in every appearance', (tester) async {
      _seedCart(_lines(1));
      await expectBuildsCleanly(
        tester,
        () => const CheckoutScreen(),
        overrides: overrides(
          providers: const [
            PaymentProviderAvailability(
              provider: PaymentProvider.vipps,
              available: true,
              enabled: true,
              configured: true,
            ),
          ],
        ),
      );
    });

    testWidgets(
      'with two providers where one is unavailable, only the available one '
      'renders as a row',
      (tester) async {
        _seedCart(_lines(1));
        await pumpBisoScreen(
          tester,
          const CheckoutScreen(),
          overrides: overrides(
            providers: const [
              PaymentProviderAvailability(
                provider: PaymentProvider.vipps,
                available: true,
                enabled: true,
                configured: true,
              ),
              PaymentProviderAvailability(
                provider: PaymentProvider.stripe,
                available: false,
                enabled: false,
                configured: false,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Vipps'), findsOneWidget);
        expect(find.text('Card'), findsNothing);
        expect(find.byType(Radio<PaymentProvider>), findsOneWidget);
      },
    );
  });
}
