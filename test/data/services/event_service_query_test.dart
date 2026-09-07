import 'package:biso/data/services/event_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
  });
}
