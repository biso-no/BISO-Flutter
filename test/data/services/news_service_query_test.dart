import 'package:biso/data/services/news_service.dart';
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
  group('NewsService.buildNewsListQueries', () {
    test('filters to published rows', () {
      final q = NewsService.buildNewsListQueries();
      expect(q, hasQuery('equal', containing: ['status', 'published']));
    });

    test('a campus list includes National', () {
      final q = NewsService.buildNewsListQueries(campusId: '2');
      expect(
        q,
        hasQuery('equal', containing: ['campus_id', '"values":["2","5"]']),
      );
    });

    test('a National list is only National', () {
      final q = NewsService.buildNewsListQueries(campusId: '5');
      expect(q, hasQuery('equal', containing: ['campus_id', '"values":["5"]']));
    });

    test('omits the campus filter without a campus', () {
      final q = NewsService.buildNewsListQueries();
      expect(q.any((s) => s.contains('campus_id')), isFalse);
    });

    test('selects translations and never filters on locale', () {
      final q = NewsService.buildNewsListQueries();
      expect(q.any((s) => s.contains('translation_refs.*')), isTrue);
      expect(q.any((s) => s.contains('translation_refs.locale')), isFalse);
    });

    test('orders newest first', () {
      final q = NewsService.buildNewsListQueries();
      expect(q, hasQuery('orderDesc', containing: [r'$createdAt']));
    });

    test('applies limit and offset', () {
      final q = NewsService.buildNewsListQueries(limit: 6, offset: 12);
      expect(q, hasQuery('limit', containing: ['[6]']));
      expect(q, hasQuery('offset', containing: ['[12]']));
    });
  });

  group('NewsService.buildNewsLookupQueries', () {
    final q = NewsService.buildNewsLookupQueries('big-news');

    test('matches by slug or id', () {
      expect(
        q,
        hasQuery(
          'or',
          containing: [
            '{"method":"equal","attribute":"slug","values":["big-news"]}',
            r'{"method":"equal","attribute":"$id","values":["big-news"]}',
          ],
        ),
      );
    });

    test('published only, with translations, single row', () {
      expect(q, hasQuery('equal', containing: ['status', 'published']));
      expect(q.any((s) => s.contains('translation_refs.*')), isTrue);
      expect(q, hasQuery('limit', containing: ['[1]']));
    });
  });
}
