import 'package:biso/data/services/job_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Appwrite serialises each query to JSON, e.g.
/// `{"method":"limit","values":[20]}`. Matching the exact `"method":"x"`
/// fragment stops `contains` also matching `containsAny`/`containsAll`.
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
  group('JobService.buildJobQueries', () {
    test('always filters to published rows', () {
      expect(
        JobService.buildJobQueries(),
        hasQuery('equal', containing: ['status', 'published']),
      );
    });

    test('selects nested translations so they are returned', () {
      expect(
        JobService.buildJobQueries(),
        hasQuery('select', containing: ['translations.*']),
      );
    });

    test('never filters on translation locale', () {
      // 73% of live jobs are Norwegian-only and 21% English-only, so a
      // locale filter would hide most of the board from every user.
      final q = JobService.buildJobQueries();
      expect(q.any((s) => s.contains('translations.locale')), isFalse);
    });

    test('filters by campus when provided', () {
      expect(
        JobService.buildJobQueries(campusId: '1'),
        hasQuery('equal', containing: ['campus_id', '"1"']),
      );
    });

    test('omits the campus filter when campusId is null', () {
      expect(
        JobService.buildJobQueries().any((s) => s.contains('campus_id')),
        isFalse,
      );
    });

    test('hides jobs whose deadline has passed, keeping those with none', () {
      final q = JobService.buildJobQueries(now: DateTime.utc(2026, 9, 8));
      expect(
        q,
        hasQuery(
          'or',
          containing: [
            'application_deadline',
            '2026-09-08T00:00:00.000Z',
            'isNull',
          ],
        ),
      );
    });

    test('includeExpired drops the deadline window entirely', () {
      final q = JobService.buildJobQueries(
        includeExpired: true,
        now: DateTime.utc(2026, 9, 8),
      );
      // The deadline *filter* is the `or(...)` clause. Matching on the bare
      // string `application_deadline` would also flag the unrelated
      // `orderAsc` clause, which must stay present even when expired jobs
      // are included.
      expect(q.any((s) => s.contains('"method":"or"')), isFalse);
    });

    test('orders ascending by application_deadline, soonest job first', () {
      final q = JobService.buildJobQueries();
      expect(q, hasQuery('orderAsc', containing: ['application_deadline']));
      // orderDesc would put the furthest-future deadline at the top of the
      // list.
      expect(q.any((s) => s.contains('"method":"orderDesc"')), isFalse);
    });

    test('keeps ordering even when includeExpired is set', () {
      final q = JobService.buildJobQueries(
        includeExpired: true,
        now: DateTime.utc(2026, 9, 8),
      );
      expect(q, hasQuery('orderAsc', containing: ['application_deadline']));
      expect(q.any((s) => s.contains('"method":"orderDesc"')), isFalse);
    });

    test('searches server-side with contains on the translated title', () {
      expect(
        JobService.buildJobQueries(search: 'advisor'),
        hasQuery('contains', containing: ['translations.title', 'advisor']),
      );
    });

    test('omits the search clause for a blank term', () {
      expect(
        JobService.buildJobQueries(
          search: '   ',
        ).any((s) => s.contains('translations.title')),
        isFalse,
      );
    });

    test('applies the requested limit and offset', () {
      final q = JobService.buildJobQueries(limit: 37, offset: 40);
      expect(q, hasQuery('limit', containing: ['37']));
      expect(q, hasQuery('offset', containing: ['40']));
    });
  });

  group('JobService.buildJobCountQueries', () {
    test('selects only the id rather than whole rows', () {
      expect(
        JobService.buildJobCountQueries(),
        hasQuery('select', containing: [r'$id']),
      );
      expect(
        JobService.buildJobCountQueries().any(
          (s) => s.contains('translations.*'),
        ),
        isFalse,
      );
    });

    test('uses the same deadline window as the list read', () {
      expect(
        JobService.buildJobCountQueries(now: DateTime.utc(2026, 9, 8)),
        hasQuery('or', containing: ['application_deadline']),
      );
    });
  });
}
