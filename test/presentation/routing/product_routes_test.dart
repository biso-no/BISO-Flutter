import 'package:biso/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// go_router matches the first sibling route that fits, so a `/:productId`
/// wildcard placed above the shop's static routes silently swallows them:
/// `/explore/products/cart` renders a product detail screen for a product
/// called "cart" instead of the cart. Nothing about the call site makes that
/// visible, and it takes out the entire cart-to-checkout flow, so the ordering
/// is pinned here.
void main() {
  List<String> pathsInOrder() => productRoutes()
      .whereType<GoRoute>()
      .map((route) => route.path)
      .toList(growable: false);

  group('productRoutes ordering', () {
    test('declares the wildcard product route exactly once', () {
      expect(
        pathsInOrder().where((path) => path == '/:productId'),
        hasLength(1),
      );
    });

    test('puts every static single-segment route above the wildcard', () {
      final paths = pathsInOrder();
      final wildcard = paths.indexOf('/:productId');
      expect(wildcard, greaterThanOrEqualTo(0));

      for (final path in ['/new', '/cart', '/checkout', '/orders']) {
        final index = paths.indexOf(path);
        expect(index, greaterThanOrEqualTo(0), reason: '$path is missing');
        expect(
          index,
          lessThan(wildcard),
          reason: '$path must be declared before /:productId or the wildcard '
              'matches it first',
        );
      }
    });

    test('keeps the multi-segment routes reachable past the wildcard', () {
      // These carry a second segment, so the one-segment wildcard cannot
      // match them and their position is not load-bearing.
      final paths = pathsInOrder();
      expect(paths, contains('/order/:orderId'));
      expect(paths, contains('/webshop/:productId'));
    });
  });
}
