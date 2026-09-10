import 'package:biso/core/constants/notification_topics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('campusSlugFor', () {
    test('maps each known campus id to its slug', () {
      expect(campusSlugFor('1'), 'oslo');
      expect(campusSlugFor('2'), 'bergen');
      expect(campusSlugFor('3'), 'trondheim');
      expect(campusSlugFor('4'), 'stavanger');
      expect(campusSlugFor('5'), 'national');
    });

    test(
      'falls back to national for a null campus, because a profile campus is '
      'optional and those students must still receive national content',
      () {
        expect(campusSlugFor(null), 'national');
      },
    );

    test('falls back to national for an unrecognised campus id', () {
      expect(campusSlugFor('99'), 'national');
      expect(campusSlugFor(''), 'national');
    });
  });

  group('appwriteTopicIdsFor', () {
    test('expands each enabled topic into its campus and national scopes', () {
      expect(
        appwriteTopicIdsFor(
          intent: const {'news': true, 'events': false, 'jobs': false, 'shop': false},
          campusId: '2',
        ),
        <String>{'general', 'news_bergen', 'news_national'},
      );
    });

    test('always includes the general topic, even with everything off', () {
      expect(
        appwriteTopicIdsFor(
          intent: const {'news': false, 'events': false, 'jobs': false, 'shop': false},
          campusId: '1',
        ),
        <String>{'general'},
      );
    });

    test(
      'does not emit a duplicate national id for a national student - the '
      'campus scope and the national scope are the same topic',
      () {
        expect(
          appwriteTopicIdsFor(
            intent: const {'news': true, 'events': false, 'jobs': false, 'shop': false},
            campusId: '5',
          ),
          <String>{'general', 'news_national'},
        );
      },
    );

    test('expands every enabled topic', () {
      expect(
        appwriteTopicIdsFor(
          intent: const {'news': true, 'events': true, 'jobs': true, 'shop': true},
          campusId: '1',
        ),
        <String>{
          'general',
          'news_oslo', 'news_national',
          'events_oslo', 'events_national',
          'jobs_oslo', 'jobs_national',
          'shop_oslo', 'shop_national',
        },
      );
    });

    test('treats a missing intent key as disabled rather than throwing', () {
      expect(
        appwriteTopicIdsFor(intent: const {}, campusId: '1'),
        <String>{'general'},
      );
    });
  });

  group('kDefaultTopicIntent', () {
    test('covers exactly the four logical topics', () {
      expect(
        kDefaultTopicIntent.keys.toSet(),
        NotificationTopic.values.map((t) => t.id).toSet(),
      );
    });
  });
}
