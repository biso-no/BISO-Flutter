import 'dart:convert';

import 'package:biso/core/utils/currency.dart';
import 'package:biso/data/models/cart_item.dart';
import 'package:biso/data/models/checkout_quote.dart';
import 'package:biso/data/models/payment_provider.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/models/webshop_product_model.dart';
import 'package:biso/data/services/shop_api_client.dart';
import 'package:biso/presentation/screens/shop/cart_screen.dart';
import 'package:biso/presentation/screens/shop/checkout_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/shop/cart_provider.dart';
import 'package:biso/providers/shop/checkout_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

/// A quote with a large per-line amount, a member discount and membership
/// applied — the worst case for R11 (amounts and counts never truncate):
/// every row in the order summary carries a wide number at once.
const _bigQuote = CheckoutQuote(
  currency: 'NOK',
  subtotal: 14814,
  discountTotal: 1234.5,
  total: 13579.5,
  membershipApplied: true,
  memberDiscountPercent: 10,
  items: [
    CheckoutQuoteLine(
      productId: 'prod-big',
      name: 'Big Ticket Item',
      title: 'Big Ticket Item',
      quantity: 12,
      unitPrice: 1234.5,
      lineTotal: 14814,
    ),
  ],
);

/// A `ShopApiClient` that never touches the network — for tests that
/// exercise a cart mutation (`removeLine`, `setQuantity`) whose reservation
/// sync would otherwise reach the real HTTP client and hang the test with a
/// pending timer.
class _NoNetworkShopApi extends ShopApiClient {
  @override
  Future<int> reserve({
    required String productId,
    required int quantity,
    Map<String, String>? customFields,
    Map<String, String>? customFieldLabels,
  }) async => quantity;

  @override
  Future<void> releaseReservation({String? productId}) async {}
}

/// Asserts [text] renders as a single, complete line: present verbatim in
/// the tree and not ellipsized (R11 — amounts and counts never truncate).
///
/// Two different rows can legitimately show the same amount (e.g. a
/// single-line cart's subtotal equals that line's own total), so this
/// checks every match rather than requiring exactly one.
void _expectWhole(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(
    finder,
    findsAtLeastNWidgets(1),
    reason: '"$text" should render in full',
  );
  for (final element in finder.evaluate()) {
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byWidget(element.widget),
    );
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: '"$text" was ellipsized or wrapped past its line cap',
    );
  }
}

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

    testWidgets(
      'a line with a large price and a double-digit quantity is never '
      'ellipsized or wrapped at 1.6x text (R11)',
      (tester) async {
        // `lineId` isn't trusted from storage — `CartItem.fromJson` always
        // recomputes it from productId/variationId/customFields (so an
        // older build's stored id still collapses correctly) — so this has
        // to come from `fromProduct`/`buildLineId` rather than a literal,
        // or the key below would look for a line that was never restored.
        final bigLine = CartItem.fromProduct(
          product: const WebshopProduct(
            id: 'prod-big',
            images: [],
            title: 'Big Ticket Item',
            regularPrice: 1234.5,
          ),
          quantity: 12,
        );
        _seedCart([bigLine]);
        await pumpBisoScreen(
          tester,
          const CartScreen(),
          overrides: [cartUserIdProvider.overrideWithValue(_buyerId)],
          textScale: 1.6,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // With a single line the cart's subtotal equals the line total, so
        // a bare `find.text` would match both the line's own price and the
        // bottom bar's subtotal — scope to the line itself.
        final lineFinder = find.byKey(ValueKey('cart-line-${bigLine.lineId}'));
        final priceFinder = find.descendant(
          of: lineFinder,
          matching: find.text(formatNok(bigLine.lineTotal)),
        );
        expect(priceFinder, findsOneWidget);
        final priceParagraph = tester.renderObject<RenderParagraph>(
          priceFinder,
        );
        expect(priceParagraph.didExceedMaxLines, isFalse);

        final quantityFinder = find.descendant(
          of: lineFinder,
          matching: find.text('12'),
        );
        expect(quantityFinder, findsOneWidget);
        final quantityParagraph = tester.renderObject<RenderParagraph>(
          quantityFinder,
        );
        expect(quantityParagraph.didExceedMaxLines, isFalse);
        // A single line of titleMedium text at 1.6x is well under 60pt; a
        // wrap to a second line (e.g. "1" over "2") would push past that.
        expect(quantityParagraph.size.height, lessThan(60));
      },
    );

    testWidgets('the remove control removes a line', (tester) async {
      final lines = _lines(2);
      _seedCart(lines);
      await pumpBisoScreen(
        tester,
        const CartScreen(),
        overrides: [
          cartUserIdProvider.overrideWithValue(_buyerId),
          // `removeLine` re-syncs the product's stock hold; give it a fake
          // client so that sync doesn't reach the network (which hangs the
          // test on a real HTTP call and leaves a pending timer behind).
          shopApiClientProvider.overrideWithValue(_NoNetworkShopApi()),
        ],
      );
      await tester.pumpAndSettle();

      final firstKey = ValueKey('cart-line-${lines.first.lineId}');
      final secondKey = ValueKey('cart-line-${lines.last.lineId}');
      expect(find.byKey(firstKey), findsOneWidget);
      expect(find.byKey(secondKey), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byKey(firstKey),
          matching: find.byTooltip('Remove'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(firstKey), findsNothing);
      expect(find.byKey(secondKey), findsOneWidget);
    });
  });

  group('Checkout', () {
    List<Override> overrides({
      required List<PaymentProviderAvailability> providers,
      CheckoutQuote quote = _quote,
    }) => [
      authStateProvider.overrideWith((_) => _Auth()),
      cartUserIdProvider.overrideWithValue(_buyerId),
      checkoutQuoteProvider.overrideWith((ref) async => quote),
      paymentProvidersProvider.overrideWith((ref) async => providers),
    ];

    const oneAvailableProvider = [
      PaymentProviderAvailability(
        provider: PaymentProvider.vipps,
        available: true,
        enabled: true,
        configured: true,
      ),
    ];

    const twoAvailableProviders = [
      PaymentProviderAvailability(
        provider: PaymentProvider.vipps,
        available: true,
        enabled: true,
        configured: true,
      ),
      PaymentProviderAvailability(
        provider: PaymentProvider.stripe,
        available: true,
        enabled: true,
        configured: true,
      ),
    ];

    testWidgets('builds on BisoPage in every appearance', (tester) async {
      _seedCart(_lines(1));
      await expectBuildsCleanly(
        tester,
        () => const CheckoutScreen(),
        overrides: overrides(providers: oneAvailableProvider),
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

    testWidgets(
      'a discounted, membership quote shows every amount in full at 1.6x '
      'text (R11)',
      (tester) async {
        _seedCart(_lines(1));
        await pumpBisoScreen(
          tester,
          const CheckoutScreen(),
          overrides: overrides(
            providers: oneAvailableProvider,
            quote: _bigQuote,
          ),
          textScale: 1.6,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // The order summary sits below the contact and payment sections; at
        // 1.6x text those alone fill the 844pt viewport, so the summary is
        // genuinely below the fold (not yet built by the lazy sliver list)
        // until scrolled into view — the same as a real device.
        await tester.fling(
          find.byType(CustomScrollView),
          const Offset(0, -4000),
          3000,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        _expectWhole(tester, formatNok(_bigQuote.items.single.lineTotal));
        _expectWhole(tester, formatNok(_bigQuote.originalTotal));
        _expectWhole(tester, '-${formatNok(_bigQuote.discountTotal)}');
        _expectWhole(tester, formatNok(_bigQuote.total));
      },
    );

    testWidgets(
      'tapping the second available provider selects it, checking its '
      'Radio and updating the pay button',
      (tester) async {
        _seedCart(_lines(1));
        await pumpBisoScreen(
          tester,
          const CheckoutScreen(),
          overrides: overrides(providers: twoAvailableProviders),
        );
        await tester.pumpAndSettle();

        // Vipps and Card's own descriptions ("Pay with Vipps MobilePay",
        // "Pay by card") also contain "with <name>" substrings, so the pay
        // button is matched by its "Pay NOK …" prefix (unique to its own
        // label) rather than a bare "with <name>" match. It also sits below
        // the order summary, past this lazy sliver list's built cache
        // extent until scrolled into view.
        Future<void> scrollToPayButton() async {
          await tester.fling(
            find.byType(CustomScrollView),
            const Offset(0, -4000),
            3000,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        // Vipps (the first available provider) is selected by default.
        await scrollToPayButton();
        expect(find.text('Pay NOK 100 with Vipps'), findsOneWidget);

        // Scroll back up to reach the "Card" row, then tap it.
        await tester.fling(
          find.byType(CustomScrollView),
          const Offset(0, 4000),
          3000,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Card'));
        await tester.pumpAndSettle();

        // Radio.adaptive reads its checked state from the ambient
        // RadioGroup rather than its own (deprecated) groupValue field, so
        // assert selection through the registry the Radios themselves read.
        final radioContext = tester.element(
          find.byType(Radio<PaymentProvider>).first,
        );
        final registry = RadioGroup.maybeOf<PaymentProvider>(radioContext);
        expect(registry?.groupValue, PaymentProvider.stripe);

        // And the pay button — the observable effect of the selection,
        // without starting a real payment — now reflects Stripe ("Card").
        await scrollToPayButton();
        expect(find.text('Pay NOK 100 with Card'), findsOneWidget);
      },
    );
  });
}
