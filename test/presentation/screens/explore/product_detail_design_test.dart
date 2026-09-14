import 'package:biso/data/models/product_model.dart';
import 'package:biso/presentation/screens/explore/product_detail_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/data/services/product_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

const _product = ProductModel(
  id: 'p1',
  name: 'A genuinely long marketplace listing title used for layout checks',
  description:
      'A great, gently used item with a description long enough to wrap '
      'across a couple of lines inside the description card.',
  price: 250,
  currency: 'NOK',
  sellerId: 'seller-1',
  sellerName: 'Kari Nordmann',
  campusId: 'oslo',
  category: 'Books',
  condition: 'good',
  images: [
    'https://example.com/a.png',
    'https://example.com/b.png',
  ],
  isNegotiable: true,
  contactMethod: 'message',
);

/// Signed out, so `_loadProduct`'s favorite-status check (gated on
/// `auth.isAuthenticated`) never runs; only `getProductById` and
/// `incrementViewCount` are exercised, both faked below.
class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth() : super(const AuthState());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Replaces the real Appwrite-backed service. Deterministic and offline.
class _FakeProductService extends ProductService {
  @override
  Future<ProductModel?> getProductById(String id) async => _product;

  @override
  Future<void> incrementViewCount(String productId) async {}
}

List<Override> _overrides() => [
  authStateProvider.overrideWith((_) => _Auth()),
  productServiceProvider.overrideWithValue(_FakeProductService()),
];

void main() {
  testWidgets('Product detail builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const ProductDetailScreen(productId: 'p1'),
      overrides: _overrides(),
      routed: true,
    );
  });

  testWidgets(
    'the gallery starts at y = 0 and the compact title is hidden at rest',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const ProductDetailScreen(productId: 'p1'),
        overrides: _overrides(),
        routed: true,
      );
      await tester.pumpAndSettle();

      final pageView = tester.getTopLeft(find.byType(PageView));
      expect(pageView.dy, 0);

      final compactTitle = tester.widget<Text>(
        find.byKey(const ValueKey('biso-compact-title')),
      );
      final opacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.byKey(const ValueKey('biso-compact-title')),
          matching: find.byType(Opacity),
        ),
      );
      expect(compactTitle.data, _product.name);
      expect(opacity.opacity, 0);
    },
  );

  testWidgets('the compact title fades in after scrolling', (tester) async {
    await pumpBisoScreen(
      tester,
      const ProductDetailScreen(productId: 'p1'),
      overrides: _overrides(),
      routed: true,
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final opacity = tester.widget<Opacity>(
      find.ancestor(
        of: find.byKey(const ValueKey('biso-compact-title')),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, greaterThan(0.9));
  });

  testWidgets('the bottom bar sits above the tab bar', (tester) async {
    await pumpBisoScreen(
      tester,
      const ProductDetailScreen(productId: 'p1'),
      overrides: _overrides(),
      routed: true,
    );
    await tester.pumpAndSettle();

    expect(find.byType(BisoBottomBar), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Contact Seller'), findsOneWidget);

    final bottomBarBottom = tester.getBottomLeft(
      find.byType(BisoBottomBar),
    ).dy;
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    // The tab bar's home-indicator inset (34pt in the harness) plus its own
    // bar height keep the bottom bar's bottom edge above the screen bottom.
    expect(bottomBarBottom, lessThan(size.height - 34));
  });

  testWidgets('the negotiable badge and category/condition chips render', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const ProductDetailScreen(productId: 'p1'),
      overrides: _overrides(),
      routed: true,
    );
    await tester.pumpAndSettle();

    expect(find.text('Negotiable'), findsOneWidget);
    expect(find.text('Books'), findsOneWidget);
    expect(find.text('good'), findsOneWidget);
    expect(find.text('250 NOK'), findsOneWidget);

    // The seller row sits below the description card, off the initial
    // viewport at this text scale.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('Kari Nordmann'), findsOneWidget);
    expect(find.text('Prefers: In-app message'), findsOneWidget);
  });

  testWidgets('favoriting is gated behind sign-in when signed out', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const ProductDetailScreen(productId: 'p1'),
      overrides: _overrides(),
      routed: true,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Favorite'));
    await tester.pump();

    expect(
      find.text('Please sign in to save favorites'),
      findsOneWidget,
    );
    // The heart stays unfilled: the toggle never reached the service.
    expect(find.byIcon(CupertinoIcons.heart), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.heart_fill), findsNothing);
  });
}
