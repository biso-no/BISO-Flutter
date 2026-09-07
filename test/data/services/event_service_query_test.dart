import 'package:biso/data/services/event_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Appwrite serialises each query to JSON, e.g.
/// `{"method":"limit","values":[20]}`. Matching on the exact `"method":"x"`
/// fragment keeps `contains` from also matching `containsAny`/`containsAll`
/// and `orderAsc` from matching `orderDesc`.
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
  group('EventService.buildEventQueries', () {
    test('always filters to published rows', () {
      final q = EventService.buildEventQueries();
      expect(q.any((s) => s.contains('status') && s.contains('published')), isTrue);
    });

    test('selects nested translations so they are returned', () {
      final q = EventService.buildEventQueries();
      expect(q.any((s) => s.contains('translation_refs.*')), isTrue);
    });

    test('never filters on translation locale', () {
      final q = EventService.buildEventQueries();
      expect(q.any((s) => s.contains('translation_refs.locale')), isFalse);
    });

    test('filters by campus when provided', () {
      final q = EventService.buildEventQueries(campusId: '1');
      expect(q.any((s) => s.contains('campus_id') && s.contains('"1"')), isTrue);
    });

    test('omits the campus filter when campusId is null', () {
      final q = EventService.buildEventQueries();
      expect(q.any((s) => s.contains('campus_id')), isFalse);
    });

    test('searches server-side with contains on the translated title', () {
      final q = EventService.buildEventQueries(search: 'dagene');
      expect(
        q.any((s) => s.contains('contains') && s.contains('translation_refs.title')),
        isTrue,
      );
    });

    test('embeds the actual search term, via contains and not a lookalike', () {
      final q = EventService.buildEventQueries(search: 'dagene');
      expect(
        q,
        hasQuery('contains', containing: ['translation_refs.title', 'dagene']),
      );
    });

    test('omits the search clause for a blank or whitespace-only term', () {
      for (final term in <String?>[null, '', '   ']) {
        final q = EventService.buildEventQueries(search: term);
        expect(
          q.any((s) => s.contains('translation_refs.title')),
          isFalse,
          reason: 'search: ${term == null ? 'null' : '"$term"'}',
        );
      }
    });

    test('excludes past events unless includePast is set', () {
      final now = DateTime.utc(2026, 9, 7);
      final upcoming = EventService.buildEventQueries(now: now);
      expect(
        upcoming.any(
          (s) => s.contains('greaterThanEqual') && s.contains('start_date'),
        ),
        isTrue,
      );

      final all = EventService.buildEventQueries(includePast: true, now: now);
      expect(
        all.any((s) => s.contains('greaterThanEqual') && s.contains('start_date')),
        isFalse,
      );
    });

    test('embeds the injected now as the start_date cutoff', () {
      final now = DateTime.utc(2026, 9, 7);
      final q = EventService.buildEventQueries(now: now);
      expect(
        q,
        hasQuery(
          'greaterThanEqual',
          containing: ['start_date', '2026-09-07T00:00:00.000Z'],
        ),
      );
    });

    test('orders ascending by start_date, soonest event first', () {
      final q = EventService.buildEventQueries();
      expect(q, hasQuery('orderAsc', containing: ['start_date']));
      // orderDesc would put the furthest-future event at the top of the list.
      expect(q.any((s) => s.contains('"method":"orderDesc"')), isFalse);
    });

    test('applies the requested limit', () {
      expect(
        EventService.buildEventQueries(limit: 37),
        hasQuery('limit', containing: ['37']),
      );
    });

    test('applies the requested offset', () {
      // Without an offset clause, infinite scroll re-fetches page 1 forever
      // and every event is duplicated down the list.
      expect(
        EventService.buildEventQueries(offset: 40),
        hasQuery('offset', containing: ['40']),
      );
      expect(
        EventService.buildEventQueries(),
        hasQuery('offset', containing: ['0']),
      );
    });
  });

  group('EventService.buildEventCountQueries', () {
    test('matches the list filters: published, campus, upcoming-only', () {
      final now = DateTime.utc(2026, 9, 7);
      final q = EventService.buildEventCountQueries(campusId: '1', now: now);

      expect(q.any((s) => s.contains('status') && s.contains('published')), isTrue);
      expect(q.any((s) => s.contains('campus_id') && s.contains('"1"')), isTrue);
      expect(
        q,
        hasQuery(
          'greaterThanEqual',
          containing: ['start_date', '2026-09-07T00:00:00.000Z'],
        ),
      );

      final all = EventService.buildEventCountQueries(
        campusId: '1',
        includePast: true,
        now: now,
      );
      expect(all.any((s) => s.contains('start_date')), isFalse);
    });

    test('never filters on translation locale', () {
      final q = EventService.buildEventCountQueries();
      expect(q.any((s) => s.contains('translation_refs.locale')), isFalse);
    });

    test('selects only \$id — the caller reads total, never the rows', () {
      final q = EventService.buildEventCountQueries();
      expect(q, hasQuery('select', containing: [r'$id']));
      expect(q.any((s) => s.contains('translation_refs.*')), isFalse);
    });

    test('asks for a single row: total is independent of limit', () {
      final q = EventService.buildEventCountQueries();
      expect(q, hasQuery('limit', containing: ['1']));
    });
  });
}
