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

/// A discounted, membership quote sized — per direct `TextPainter`
/// measurement against `PremiumTheme`, reported in the fix-round-3 section
/// of the task report — so every amount piece fits the ~326pt-wide
/// checkout order-summary row at 1.6x text, *in this test harness's
/// synthetic fallback font* (~2x wider per character than the app's real
/// fonts, since no `flutter_test_config.dart` loads them for widget
/// tests):
/// - `bodyLarge` (17pt) pieces — every per-line amount, Subtotal
///   ("NOK 705"), and the discount ("-NOK 120.50") — measure ≤297pt,
///   comfortably under the row's width as a single, unsplit line.
/// - `headlineMedium` (28pt, the Total's style — the larger of the two
///   sizes either screen uses) is where a large number stops fitting
///   alongside a label at all, well before it stops fitting *alone*:
///   the combined "NOK 584.50" measures 445pt (> 326pt, so tier 3
///   engages), but the number piece alone — "584.50" — measures only
///   267pt, comfortably under 326pt once split from "NOK". This
///   deliberately forces `_AmountRow`'s tier 3.
const _bigQuote = CheckoutQuote(
  currency: 'NOK',
  subtotal: 705,
  discountTotal: 120.5,
  total: 584.5,
  membershipApplied: true,
  memberDiscountPercent: 15,
  items: [
    CheckoutQuoteLine(
      productId: 'prod-big',
      name: 'Big Ticket Item',
      title: 'Big Ticket Item',
      quantity: 1,
      unitPrice: 700,
      lineTotal: 700,
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

/// Asserts [text] (an amount, or the item count) renders as a single,
/// complete, full-size line wherever it appears — R11: amounts and counts
/// never truncate, wrap, or scale down. Checks, for every match:
/// - not inside a `FittedBox` (which would mean it was scaled down);
/// - `RenderParagraph.maxLines == 1` (it is a genuine single-line piece,
///   not a fallback that could itself wrap or break);
/// - `didExceedMaxLines == false` (nothing was ellipsized);
/// - laid-out width `>=` the paragraph's own maximum intrinsic width (not
///   narrower than it naturally needs, i.e. not clipped either).
///
/// This only ever holds for a piece meant to stand alone on one line. A
/// [_AmountRow] amount too wide even for a whole row to itself is split
/// into two such pieces (the currency code and the number) — each is
/// exactly this kind of one-line piece, and is asserted the same way, but
/// as two separate matches; see [_expectFullSizeSplitAmount].
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
      paragraph.maxLines,
      1,
      reason: '"$text" should be a genuine single-line piece, not a '
          'fallback that could itself wrap or break mid-content',
    );
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: '"$text" was ellipsized',
    );
    final maxIntrinsicWidth = paragraph.getMaxIntrinsicWidth(double.infinity);
    expect(
      paragraph.size.width,
      greaterThanOrEqualTo(maxIntrinsicWidth - 0.5),
      reason: '"$text" was laid out narrower than its natural width, so '
          'it was scaled down or clipped',
    );
  }
}

/// Asserts a [_AmountRow] tier-3 amount: [fullAmount] (e.g. "NOK 584.50")
/// is not rendered as one piece at all — it is split, on the single space
/// `formatNok` always produces, into the currency code and the number,
/// each its own paragraph satisfying [_expectFullSizeAmount] independently.
/// This is what actually rules out a mid-number break: two single-line
/// paragraphs can only ever wrap *between* each other, never inside either
/// one, the way one unbounded paragraph could.
void _expectFullSizeSplitAmount(WidgetTester tester, String fullAmount) {
  expect(
    find.text(fullAmount),
    findsNothing,
    reason: '"$fullAmount" should be split into separate currency/number '
        'pieces, not rendered as one paragraph',
  );
  for (final piece in fullAmount.split(' ')) {
    _expectFullSizeAmount(tester, piece);
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
        // One line, quantity 12, priced so the subtotal is a big, realistic
        // number that still fits the bar's ~342pt width as a single,
        // unsplit line at `headlineMedium`/1.6x in this harness's font:
        // "NOK 999" measures 311.5pt (per the same `TextPainter` method
        // used for the checkout fixture above) — under 342pt with margin
        // to spare, so this exercises the ordinary single-line case rather
        // than forcing `_SubtotalAmount`'s own split fallback (the next
        // test forces that path).
        final bigCart = [
          CartItem.fromProduct(
            product: const WebshopProduct(
              id: 'prod-huge',
              images: [],
              title: 'Huge Order',
              regularPrice: 83.25,
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

        _expectFullSizeAmount(tester, '12 items');

        final subtotal = bigCart.single.lineTotal;
        expect(formatNok(subtotal), 'NOK 999');
        _expectFullSizeAmount(tester, formatNok(subtotal));
      },
    );

    testWidgets(
      'a subtotal too wide for the bar splits into currency and number, '
      'and is still read as one amount at 1.6x text (R11)',
      (tester) async {
        // Sized to force `_SubtotalAmount`'s split branch. Per direct
        // `TextPainter` measurement against `PremiumTheme` at
        // `headlineMedium`/1.6x in this harness's synthetic font (reported
        // in the fix-round-4 section of the task report): "NOK 1200"
        // measures 356pt, wider than the bar's 342pt content width, while
        // the number piece "1200" measures 178pt and "NOK" 133.5pt, so
        // each piece still fits a line of its own.
        final wideCart = [
          CartItem.fromProduct(
            product: const WebshopProduct(
              id: 'prod-wide',
              images: [],
              title: 'Wide Order',
              regularPrice: 100,
            ),
            quantity: 12,
          ),
        ];
        _seedCart(wideCart);
        final semantics = tester.ensureSemantics();
        await pumpBisoScreen(
          tester,
          const CartScreen(),
          overrides: [cartUserIdProvider.overrideWithValue(_buyerId)],
          textScale: 1.6,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final subtotal = formatNok(wideCart.single.lineTotal);
        expect(subtotal, 'NOK 1200');

        // The bar's subtotal is split; the line's own (smaller) total is
        // the same string, so scope the "not one paragraph" check to the
        // bottom bar rather than the whole screen.
        final bar = find.byType(BisoBottomBar);
        expect(
          find.descendant(of: bar, matching: find.text(subtotal)),
          findsNothing,
          reason: '"$subtotal" should be split into separate currency/number '
              'pieces in the bottom bar, not rendered as one paragraph',
        );
        for (final piece in subtotal.split(' ')) {
          _expectFullSizeAmount(tester, piece);
        }

        // A screen reader must announce the amount as one phrase, not
        // "NOK" and "1200" as two separate elements.
        expect(
          find.descendant(
            of: bar,
            matching: find.bySemanticsLabel(RegExp(r'^NOK\s+1200$')),
          ),
          findsOneWidget,
          reason: 'the split subtotal should be one semantics node',
        );
        expect(find.bySemanticsLabel('NOK'), findsNothing);
        expect(find.bySemanticsLabel('1200'), findsNothing);
        semantics.dispose();
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
      bool isMember = false,
    }) => [
      authStateProvider.overrideWith((_) => _Auth()),
      hasValidMembershipProvider.overrideWithValue(isMember),
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

    const membersHoodie = WebshopProduct(
      id: 'prod-members',
      images: [],
      slug: 'members-hoodie',
      title: 'Members hoodie',
      regularPrice: 299,
      stock: 20,
      memberOnly: true,
    );

    testWidgets(
      'a non-member cannot pay for a cart holding a members-only product',
      (tester) async {
        _seedCart([CartItem.fromProduct(product: membersHoodie)]);
        await pumpBisoScreen(
          tester,
          const CheckoutScreen(),
          overrides: overrides(providers: oneAvailableProvider),
        );
        await tester.pumpAndSettle();

        final scrollable = _pageScrollable(tester);
        scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Members hoodie is only for BISO members'),
          findsOneWidget,
        );
        final pay = tester.widget<ButtonStyleButton>(
          find.ancestor(
            of: find.text('Members only'),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        );
        expect(pay.onPressed, isNull);
      },
    );

    testWidgets('a member can pay for a members-only product', (tester) async {
      _seedCart([CartItem.fromProduct(product: membersHoodie)]);
      await pumpBisoScreen(
        tester,
        const CheckoutScreen(),
        overrides: overrides(providers: oneAvailableProvider, isMember: true),
      );
      await tester.pumpAndSettle();

      final scrollable = _pageScrollable(tester);
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();

      expect(find.textContaining('only for BISO members'), findsNothing);
      expect(find.text('Pay ${formatNok(100)} with Vipps'), findsOneWidget);
    });

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

        // Per-line, Subtotal and the discount are ordinary bodyLarge
        // amounts: each fits the row as a single, unsplit line.
        _expectFullSizeAmount(tester, formatNok(_bigQuote.items.first.lineTotal));
        _expectFullSizeAmount(tester, formatNok(_bigQuote.originalTotal));
        _expectFullSizeAmount(tester, '-${formatNok(_bigQuote.discountTotal)}');

        // The Total is deliberately sized (see `_bigQuote`'s doc comment)
        // so the combined "NOK 584.50" doesn't fit the row at
        // `headlineMedium`/1.6x, but the number alone does — forcing
        // `_AmountRow`'s tier 3: the currency code and the number render
        // as two separate single-line paragraphs rather than one that
        // could break mid-number.
        _expectFullSizeSplitAmount(tester, formatNok(_bigQuote.total));

        // The long-titled second line: its amount is still shown in full
        // (same check), and its title — plenty of room beside a narrow
        // "NOK 5" — wraps onto a second line instead of ellipsizing.
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
