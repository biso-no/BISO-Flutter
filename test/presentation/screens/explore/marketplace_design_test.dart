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
    title: 'Webshop Product $i',
    regularPrice: 100.0 + i,
  ),
);

/// Base overrides shared by every test: a ready campus, a signed-out user
/// (see `_Auth`), and the marketplace feature flag / product providers set
/// deterministically so no real Appwrite call is ever made.
List<Override> _overrides({
  bool marketplaceEnabled = false,
  int cartCount = 0,
  List<WebshopProduct> webshopProducts = const [],
}) => [
  filterCampusProvider.overrideWithValue(_campus),
  campusInitializedProvider.overrideWithValue(true),
  authStateProvider.overrideWith((_) => _Auth()),
  marketplaceFeatureEnabledProvider.overrideWith(
    (ref) async => marketplaceEnabled,
  ),
  cartItemCountProvider.overrideWithValue(cartCount),
  // Marketplace listings stay empty in every test: `_PremiumProductCard`
  // would otherwise call the real `ProductService` for its favorite check.
  productsProvider.overrideWith((ref, query) async => const <ProductModel>[]),
  webshopProductsProvider.overrideWith((ref, query) async => webshopProducts),
];

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
    expect(find.text('Webshop Product 0'), findsOneWidget);
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
}
