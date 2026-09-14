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

/// A line title long enough to need two lines beside its own (narrow, so
/// side-by-side mode applies) amount, at 1.6x text on a 390pt phone — used
/// to exercise the side-by-side layout's "label may wrap" branch. The
/// price is kept small deliberately: at `_AmountRow`'s 40%-for-the-label
/// rule, a wider amount claims more of the row and leaves the label too
/// little width to demonstrate a clean two-line wrap.
const _longTicketName = 'Gala Dinner';

/// A quote with a large per-line amount, a member discount and membership
/// applied — the worst case for R11 (amounts and counts never truncate):
/// every row in the order summary carries a wide number at once — plus a
/// second, cheaply-priced line whose title is long enough to force a
/// two-line wrap beside its amount.
const _bigQuote = CheckoutQuote(
  currency: 'NOK',
  subtotal: 14819,
  discountTotal: 1234.5,
  total: 13584.5,
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
    CheckoutQuoteLine(
      productId: 'prod-long-title',
      name: _longTicketName,
      title: _longTicketName,
      quantity: 1,
      unitPrice: 5,
      lineTotal: 5,
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

/// The page's own scroll position — as opposed to one of the (also
/// `Scrollable`-backed) `TextFormField`s in the contact section, which
/// `find.byType(Scrollable).first` can just as easily match, since they're
/// nested inside the same `CustomScrollView`. The page's is reliably the
/// one with by far the largest scroll range.
ScrollableState _pageScrollable(WidgetTester tester) {
  return find
      .byType(Scrollable)
      .evaluate()
      .map((element) => (element as StatefulElement).state as ScrollableState)
      .reduce(
        (a, b) => a.position.maxScrollExtent > b.position.maxScrollExtent
            ? a
            : b,
      );
}

/// Asserts [text] (an amount) is never scaled down and never silently
/// clipped, wherever it appears — R11: amounts and counts never truncate or
/// scale down. It must not sit inside a `FittedBox`, and it must not be
/// ellipsized past a line cap ([RenderParagraph.didExceedMaxLines]).
///
/// When it renders on a single line (`RenderParagraph.maxLines == 1` — the
/// normal case for every amount except an extreme value in the much larger
/// `headlineMedium` Total style), that line must reach the amount's full
/// natural width, proving it wasn't clipped to fit. `_AmountRow`'s rare
/// fallback instead lets an amount that doesn't fit even alone on its own
/// row wrap onto more than one line rather than clip or scale — genuinely
/// full text, just not on one line — so a wrapped amount (`maxLines` left
/// unset) is checked only for the no-FittedBox/no-ellipsis conditions,
/// which is what actually rules out data loss in that case.
///
/// Two different rows can legitimately show the same amount (e.g. a
/// single-line cart's subtotal equals that line's own total), so this
/// checks every match rather than requiring exactly one.
void _expectFullSizeAmount(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(
    finder,
    findsAtLeastNWidgets(1),
    reason: '"$text" should render in full',
  );
  for (final element in finder.evaluate()) {
    final widgetFinder = find.byWidget(element.widget);
    expect(
      find.ancestor(of: widgetFinder, matching: find.byType(FittedBox)),
      findsNothing,
      reason: '"$text" is inside a FittedBox and so may be scaled down '
          'rather than shown at its natural size',
    );
    final paragraph = tester.renderObject<RenderParagraph>(widgetFinder);
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: '"$text" was ellipsized or wrapped past its line cap',
    );
    if (paragraph.maxLines == 1) {
      final maxIntrinsicWidth = paragraph.getMaxIntrinsicWidth(
        double.infinity,
      );
      expect(
        paragraph.size.width,
        greaterThanOrEqualTo(maxIntrinsicWidth - 0.5),
        reason: '"$text" was laid out narrower than its natural width, so '
            'it was scaled down or clipped',
      );
    }
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

    testWidgets(
      'the bottom bar shows the item count and a large subtotal in full '
      'at 1.6x text (R11)',
      (tester) async {
        // One line, quantity 12, priced so the subtotal is an exact,
        // realistic-looking big number ("NOK 13579.50") — the same shape
        // of number the checkout side is tested with.
        final bigCart = [
          CartItem.fromProduct(
            product: const WebshopProduct(
              id: 'prod-huge',
              images: [],
              title: 'Huge Order',
              regularPrice: 1131.625,
            ),
            quantity: 12,
          ),
        ];
        _seedCart(bigCart);
        await pumpBisoScreen(
          tester,
          const CartScreen(),
          overrides: [cartUserIdProvider.overrideWithValue(_buyerId)],
          textScale: 1.6,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final countFinder = find.text('12 items');
        expect(countFinder, findsOneWidget);
        expect(
          tester.renderObject<RenderParagraph>(countFinder).didExceedMaxLines,
          isFalse,
        );

        final subtotal = bigCart.single.lineTotal;
        expect(formatNok(subtotal), 'NOK 13579.50');
        _expectFullSizeAmount(tester, formatNok(subtotal));
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
        textScale: 1.6,
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
        // until scrolled into view — the same as a real device. `jumpTo`
        // reaches the exact bottom regardless of content height at this
        // text scale.
        final summaryScrollable = _pageScrollable(tester);
        summaryScrollable.position.jumpTo(
          summaryScrollable.position.maxScrollExtent,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        _expectFullSizeAmount(tester, formatNok(_bigQuote.items.first.lineTotal));
        _expectFullSizeAmount(tester, formatNok(_bigQuote.originalTotal));
        _expectFullSizeAmount(tester, '-${formatNok(_bigQuote.discountTotal)}');
        _expectFullSizeAmount(tester, formatNok(_bigQuote.total));

        // The long-titled second line: its amount is still shown in full
        // (same check), and its title — plenty of room beside a narrow
        // "NOK 250" — wraps onto a second line instead of ellipsizing.
        _expectFullSizeAmount(tester, formatNok(_bigQuote.items.last.lineTotal));
        final titleFinder = find.text(_longTicketName);
        expect(titleFinder, findsOneWidget);
        final titleParagraph = tester.renderObject<RenderParagraph>(titleFinder);
        expect(
          titleParagraph.didExceedMaxLines,
          isFalse,
          reason: 'the long title should fit within its 2-line cap',
        );
        // Compare against a real single line of the same style/text scale,
        // rather than a made-up ratio, to confirm it actually wrapped.
        final titleContext = tester.element(titleFinder);
        final singleLine = TextPainter(
          text: TextSpan(
            text: 'X',
            style: Theme.of(titleContext).textTheme.titleMedium,
          ),
          textDirection: Directionality.of(titleContext),
          textScaler: MediaQuery.textScalerOf(titleContext),
        )..layout();
        expect(
          titleParagraph.size.height,
          greaterThan(singleLine.height * 1.3),
          reason: 'the long title should actually wrap onto a second line, '
              'not merely fit on one',
        );
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
          textScale: 1.6,
        );
        await tester.pumpAndSettle();

        // Vipps and Card's own descriptions ("Pay with Vipps MobilePay",
        // "Pay by card") also contain "with <name>" substrings, so the pay
        // button is matched by its "Pay NOK …" prefix (unique to its own
        // label) rather than a bare "with <name>" match. It also sits below
        // the order summary, past this lazy sliver list's built cache
        // extent until scrolled into view. `jumpTo` (rather than `fling`,
        // whose distance would need re-tuning for every text scale) always
        // reaches the exact top/bottom regardless of how tall the content
        // at the current text scale is.
        Future<void> scrollToPayButton() async {
          final scrollable = _pageScrollable(tester);
          scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        // Vipps (the first available provider) is selected by default.
        await scrollToPayButton();
        expect(find.text('Pay NOK 100 with Vipps'), findsOneWidget);

        // The "Card" row is already built (it was on-screen before this
        // scroll to the pay button), just no longer within the viewport —
        // scroll it back into view rather than assuming a fixed position.
        // `ensureVisible` aligns it to the very top edge, which sits behind
        // BisoPage's floating translucent header, so nudge down a bit more
        // to land the tap on the row itself rather than the header.
        await tester.ensureVisible(find.text('Card'));
        await tester.pumpAndSettle();
        final cardScrollable = _pageScrollable(tester);
        cardScrollable.position.jumpTo(
          (cardScrollable.position.pixels - 100).clamp(
            0.0,
            cardScrollable.position.maxScrollExtent,
          ),
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
