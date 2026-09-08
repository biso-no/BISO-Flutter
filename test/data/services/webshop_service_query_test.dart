import 'package:biso/data/services/webshop_service.dart';
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
  group('WebshopService.buildProductQueries', () {
    test('always filters to published rows', () {
      expect(
        WebshopService.buildProductQueries(),
        hasQuery('equal', containing: ['status', 'published']),
      );
    });

    test('selects translations, variations and custom fields', () {
      final q = WebshopService.buildProductQueries();
      expect(q, hasQuery('select', containing: ['translation_refs.*']));
      expect(q, hasQuery('select', containing: ['variations.*']));
      expect(q, hasQuery('select', containing: ['custom_fields.*']));
    });

    test('never filters on translation locale', () {
      expect(
        WebshopService.buildProductQueries().any(
          (s) => s.contains('translation_refs.locale'),
        ),
        isFalse,
      );
    });

    test('filters by campus when provided, omits it otherwise', () {
      expect(
        WebshopService.buildProductQueries(campusId: '3'),
        hasQuery('equal', containing: ['campus_id', '"3"']),
      );
      expect(
        WebshopService.buildProductQueries().any((s) => s.contains('campus_id')),
        isFalse,
      );
    });

    test('searches server-side with contains on the translated title', () {
      expect(
        WebshopService.buildProductQueries(search: 'genser'),
        hasQuery('contains', containing: ['translation_refs.title', 'genser']),
      );
    });

    test('omits the search clause for a blank term', () {
      expect(
        WebshopService.buildProductQueries(search: '   ').any(
          (s) => s.contains('translation_refs.title'),
        ),
        isFalse,
      );
    });

    test('orders descending by \$createdAt, newest product first', () {
      final q = WebshopService.buildProductQueries();
      expect(q, hasQuery('orderDesc', containing: [r'$createdAt']));
      // orderAsc would put the oldest product at the top of the list. More
      // than cosmetics: the list pages by offset, so without one stable
      // order the pages would duplicate and skip items.
      expect(q.any((s) => s.contains('"method":"orderAsc"')), isFalse);
    });

    test('applies the requested limit and offset', () {
      final q = WebshopService.buildProductQueries(limit: 37, offset: 40);
      expect(q, hasQuery('limit', containing: ['37']));
      expect(q, hasQuery('offset', containing: ['40']));
    });
  });

  group('WebshopService.buildProductCountQueries', () {
    test('selects only the id, not whole rows or relations', () {
      final q = WebshopService.buildProductCountQueries();
      expect(q, hasQuery('select', containing: [r'$id']));
      expect(q.any((s) => s.contains('variations.*')), isFalse);
      expect(q.any((s) => s.contains('translation_refs.*')), isFalse);
    });

    test('shares the published and campus filters with the list read', () {
      final q = WebshopService.buildProductCountQueries(campusId: '3');
      expect(q, hasQuery('equal', containing: ['status', 'published']));
      expect(q, hasQuery('equal', containing: ['campus_id', '"3"']));
    });
  });
}
