import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/models/product_model.dart';
import 'package:biso/data/models/webshop_product_model.dart';
import 'package:biso/presentation/screens/explore/marketplace_screen.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/shop/cart_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

const _campus = CampusModel(
  id: 'oslo',
  name: 'Oslo',
  description: 'Test campus',
  location: 'Oslo',
  imageUrl: '',
  heroImageUrl: '',
  stats: CampusStats(),
);

/// Signed out, so `_PremiumProductCard`'s favorite check (which calls
/// `ProductService()` directly rather than through an injectable provider)
/// never runs: it is gated on `auth.isAuthenticated`.
class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth() : super(const AuthState());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<WebshopProduct> _webshopProducts(int count) => List.generate(
  count,
  (i) => WebshopProduct(
    id: 'w$i',
    images: const [],
    // Long enough to wrap the card's 2-line title at every column width the
    // grid test harness produces.
    title: 'A genuinely long webshop product title that wraps to two lines $i',
    regularPrice: 100.0 + i,
  ),
);

/// Realistic marketplace listings: a two-line title, a seller name, and a
/// condition, so `_PremiumProductCard`'s extra seller/condition row is
/// actually exercised. Favorite status is never checked for these in tests
/// because `_Auth` below always renders signed out.
List<ProductModel> _marketplaceProducts(int count) => List.generate(
  count,
  (i) => ProductModel(
    id: 'm$i',
    name: 'A genuinely long marketplace listing title that wraps twice $i',
    description: 'desc',
    price: 250.0 + i,
    sellerId: 'seller-$i',
    sellerName: 'A Fairly Long Seller Display Name $i',
    campusId: _campus.id,
    category: 'books',
    condition: 'good',
  ),
);

/// Base overrides shared by every test: a ready campus, a signed-out user
/// (see `_Auth`), and the marketplace feature flag / product providers set
/// deterministically so no real Appwrite call is ever made.
List<Override> _overrides({
  bool marketplaceEnabled = false,
  int cartCount = 0,
  List<ProductModel> products = const [],
  List<WebshopProduct> webshopProducts = const [],
}) => [
  filterCampusProvider.overrideWithValue(_campus),
  campusInitializedProvider.overrideWithValue(true),
  authStateProvider.overrideWith((_) => _Auth()),
  marketplaceFeatureEnabledProvider.overrideWith(
    (ref) async => marketplaceEnabled,
  ),
  cartItemCountProvider.overrideWithValue(cartCount),
  // Defaults to empty: `_PremiumProductCard` would otherwise call the real
  // `ProductService` for its favorite check if a test both renders
  // marketplace products AND signs the fake user in. `_Auth` below always
  // renders signed out, so passing `products` is safe even so.
  productsProvider.overrideWith((ref, query) async => products),
  webshopProductsProvider.overrideWith((ref, query) async => webshopProducts),
];

/// (card bottom − bottom of its lowest `Text`) must not exceed this, beyond
/// the info column's own bottom padding — see `_expectCardsFitContent`.
const _maxBlankBelowText = 24.0;

/// `EdgeInsets.fromLTRB(12, 8, 12, 8)` in both `_WebshopProductCard` and
/// `_PremiumProductCard`'s info `Padding`: only the bottom 8 is relevant to
/// the blank-space measurement below.
const _cardBottomPadding = 8.0;

/// Asserts every currently-built product card (grid items are lazily built,
/// so only the ones the viewport reached) has no `RenderFlex` overflow and
/// leaves no more than [_maxBlankBelowText] (plus the card's own bottom
/// padding) of blank space below its lowest line of text.
///
/// The cards (`_WebshopProductCard`/`_PremiumProductCard`) are private to
/// `marketplace_screen.dart` and so cannot be found by type from this test
/// file. Each renders exactly one `Material` as its own root widget (the
/// card surface), and nothing else in the tree puts a `Material` inside the
/// grid, so `Material` descendants of the `SliverGrid` are the most robust
/// finder available here: one match per rendered card, independent of the
/// card's (private) class name.
void _expectCardsFitContent(WidgetTester tester) {
  expect(tester.takeException(), isNull);

  final cards = find.descendant(
    of: find.byType(SliverGrid),
    matching: find.byType(Material),
  );
  final cardCount = cards.evaluate().length;
  expect(cardCount, greaterThan(0), reason: 'expected at least one product card');

  for (var i = 0; i < cardCount; i++) {
    final card = cards.at(i);
    final cardRect = tester.getRect(card);
    final texts = find.descendant(of: card, matching: find.byType(Text));
    var lowestTextBottom = cardRect.top;
    for (var t = 0; t < texts.evaluate().length; t++) {
      final textBottom = tester.getRect(texts.at(t)).bottom;
      if (textBottom > lowestTextBottom) lowestTextBottom = textBottom;
    }
    final blank = cardRect.bottom - lowestTextBottom;
    expect(
      blank,
      lessThanOrEqualTo(_maxBlankBelowText + _cardBottomPadding),
      reason:
          'card $i leaves ${blank}pt of blank space below its lowest text '
          'line (card rect: $cardRect)',
    );
  }
}

void main() {
  testWidgets('Marketplace builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const MarketplaceScreen(),
      routed: true,
      overrides: _overrides(webshopProducts: _webshopProducts(2)),
    );
  });

  testWidgets(
    'the cart badge shows the fake cartItemCountProvider count in webshop '
    'mode',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const MarketplaceScreen(),
        routed: true,
        overrides: _overrides(cartCount: 3, webshopProducts: _webshopProducts(1)),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Your cart, 3 items'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    },
  );

  testWidgets('the grid of webshop products is a SliverGrid', (tester) async {
    await pumpBisoScreen(
      tester,
      const MarketplaceScreen(),
      routed: true,
      overrides: _overrides(webshopProducts: _webshopProducts(2)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SliverGrid), findsOneWidget);
    expect(find.textContaining('webshop product title'), findsWidgets);
  });

  testWidgets(
    'the sell action only exists in marketplace mode, not webshop mode',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const MarketplaceScreen(),
        routed: true,
        overrides: _overrides(marketplaceEnabled: true),
      );
      await tester.pumpAndSettle();

      // Starts in webshop mode: no sell action, but the mode toggle chips
      // are both present.
      final marketplaceChip = find.widgetWithText(ChoiceChip, 'Marketplace');
      final webshopChip = find.widgetWithText(ChoiceChip, 'Webshop');
      expect(find.byTooltip('Sell Item'), findsNothing);
      expect(marketplaceChip, findsOneWidget);
      expect(webshopChip, findsOneWidget);

      await tester.tap(marketplaceChip);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Sell Item'), findsOneWidget);
      // Marketplace listings settle student-to-student, not through the
      // BISO cart.
      expect(find.byTooltip('Your cart'), findsNothing);
    },
  );

  testWidgets('search is in the header, not a fixed field', (tester) async {
    await pumpBisoScreen(
      tester,
      const MarketplaceScreen(),
      routed: true,
      overrides: _overrides(webshopProducts: _webshopProducts(1)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });

  // The grid's `mainAxisExtent` is computed from the card's actual content
  // (see `_gridMainAxisExtent` in marketplace_screen.dart) rather than a
  // fixed `childAspectRatio`, because no single ratio fits both text scales
  // and both card shapes (marketplace cards carry an extra seller/condition
  // row webshop cards don't). Both modes, both scales: no overflow, no
  // large blank band.
  for (final textScale in [1.0, 1.6]) {
    testWidgets(
      'webshop cards fit their content with no overflow and no more than '
      '${_maxBlankBelowText}pt of blank space at ${textScale}x text',
      (tester) async {
        await pumpBisoScreen(
          tester,
          const MarketplaceScreen(),
          routed: true,
          textScale: textScale,
          overrides: _overrides(webshopProducts: _webshopProducts(4)),
        );
        await tester.pumpAndSettle();

        _expectCardsFitContent(tester);
      },
    );

    testWidgets(
      'marketplace cards fit their content with no overflow and no more '
      'than ${_maxBlankBelowText}pt of blank space at ${textScale}x text',
      (tester) async {
        await pumpBisoScreen(
          tester,
          const MarketplaceScreen(),
          routed: true,
          textScale: textScale,
          overrides: _overrides(
            marketplaceEnabled: true,
            products: _marketplaceProducts(4),
            webshopProducts: _webshopProducts(4),
          ),
        );
        await tester.pumpAndSettle();

        // Starts in webshop mode; switch to marketplace to exercise its
        // extra seller/condition row.
        await tester.tap(find.widgetWithText(ChoiceChip, 'Marketplace'));
        await tester.pumpAndSettle();

        _expectCardsFitContent(tester);
      },
    );
  }
}
