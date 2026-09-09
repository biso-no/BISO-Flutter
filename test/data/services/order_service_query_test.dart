import 'package:biso/data/services/order_service.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher hasQuery(String method, {List<String> containing = const []}) {
  return predicate<List<String>>(
    (queries) => queries.any(
      (q) =>
          q.contains('"method":"$method"') &&
          containing.every((fragment) => q.contains(fragment)),
    ),
    'has a "$method" query containing ${containing.join(', ')}',
  );
}

void main() {
  group('OrderService.buildHistoryQueries', () {
    test('selects the nested lines the receipt renders', () {
      final queries = OrderService.buildHistoryQueries();
      expect(queries, hasQuery('select', containing: ['order_items.*']));
      expect(
        queries,
        hasQuery('select', containing: ['order_items.variation.*']),
      );
      expect(
        queries,
        hasQuery('select', containing: ['order_items.field_answers.*']),
      );
    });

    test('shows the newest order first', () {
      expect(
        OrderService.buildHistoryQueries(),
        hasQuery('orderDesc', containing: [r'$createdAt']),
      );
    });

    test('never filters on userId', () {
      // Row-level security already scopes the read to the caller's own orders.
      // A userId filter would additionally hide any order whose column does not
      // match the current account id — silently losing a buyer's history.
      expect(
        OrderService.buildHistoryQueries().any((q) => q.contains('userId')),
        isFalse,
      );
    });

    test('passes the requested page through', () {
      final queries = OrderService.buildHistoryQueries(limit: 5, offset: 10);
      expect(queries, hasQuery('limit', containing: ['5']));
      expect(queries, hasQuery('offset', containing: ['10']));
    });
  });
}
