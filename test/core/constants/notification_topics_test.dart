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
          intent: const {
            'news': true,
            'events': false,
            'jobs': false,
            'shop': false,
          },
          campusId: '2',
          locale: 'no',
        ),
        <String>{
          'general_no',
          'general_bergen_no',
          'news_bergen_no',
          'news_national_no',
        },
      );
    });

    test('always includes the general topic, even with everything off', () {
      expect(
        appwriteTopicIdsFor(
          intent: const {
            'news': false,
            'events': false,
            'jobs': false,
            'shop': false,
          },
          campusId: '1',
          locale: 'no',
        ),
        <String>{'general_no', 'general_oslo_no'},
      );
    });

    test('does not emit a duplicate national id for a national student - the '
        'campus scope and the national scope are the same topic', () {
      expect(
        appwriteTopicIdsFor(
          intent: const {
            'news': true,
            'events': false,
            'jobs': false,
            'shop': false,
          },
          campusId: '5',
          locale: 'no',
        ),
        <String>{'general_no', 'news_national_no'},
      );
    });

    test('expands every enabled topic', () {
      expect(
        appwriteTopicIdsFor(
          intent: const {
            'news': true,
            'events': true,
            'jobs': true,
            'shop': true,
          },
          campusId: '1',
          locale: 'no',
        ),
        <String>{
          'general_no',
          'general_oslo_no',
          'news_oslo_no',
          'news_national_no',
          'events_oslo_no',
          'events_national_no',
          'jobs_oslo_no',
          'jobs_national_no',
          'shop_oslo_no',
          'shop_national_no',
        },
      );
    });

    test('treats a missing intent key as disabled rather than throwing', () {
      expect(
        appwriteTopicIdsFor(intent: const {}, campusId: '1', locale: 'no'),
        <String>{'general_no', 'general_oslo_no'},
      );
    });
  });

  group('language-suffixed topics', () {
    test(
      'a Bergen student following events gets Bergen and national, in one language',
      () {
        expect(
          appwriteTopicIdsFor(
            intent: const {'events': true},
            campusId: '2',
            locale: 'no',
          ),
          <String>{
            'general_no',
            'general_bergen_no',
            'events_bergen_no',
            'events_national_no',
          },
        );
      },
    );

    test(
      'a National or campus-less student has no campus everyone channel',
      () {
        expect(
          appwriteTopicIdsFor(intent: const {}, campusId: '5', locale: 'en'),
          <String>{'general_en'},
        );
        expect(
          appwriteTopicIdsFor(intent: const {}, campusId: null, locale: 'en'),
          <String>{'general_en'},
        );
      },
    );

    test('never mixes languages', () {
      final ids = appwriteTopicIdsFor(
        intent: kDefaultTopicIntent,
        campusId: '1',
        locale: 'en',
      );
      expect(ids.every((id) => id.endsWith('_en')), isTrue);
    });

    test('pushLocaleFor maps Norwegian variants', () {
      for (final c in ['no', 'nb', 'nn', 'NB']) {
        expect(pushLocaleFor(c), 'no');
      }
      for (final c in ['en', 'sv', 'de', '']) {
        expect(pushLocaleFor(c), 'en');
      }
    });

    test('allPushTopicIds matches the server list exactly', () {
      expect(<String>[...allPushTopicIds()]..sort(), <String>[
        'events_bergen_en',
        'events_bergen_no',
        'events_national_en',
        'events_national_no',
        'events_oslo_en',
        'events_oslo_no',
        'events_stavanger_en',
        'events_stavanger_no',
        'events_trondheim_en',
        'events_trondheim_no',
        'general_bergen_en',
        'general_bergen_no',
        'general_en',
        'general_no',
        'general_oslo_en',
        'general_oslo_no',
        'general_stavanger_en',
        'general_stavanger_no',
        'general_trondheim_en',
        'general_trondheim_no',
        'jobs_bergen_en',
        'jobs_bergen_no',
        'jobs_national_en',
        'jobs_national_no',
        'jobs_oslo_en',
        'jobs_oslo_no',
        'jobs_stavanger_en',
        'jobs_stavanger_no',
        'jobs_trondheim_en',
        'jobs_trondheim_no',
        'news_bergen_en',
        'news_bergen_no',
        'news_national_en',
        'news_national_no',
        'news_oslo_en',
        'news_oslo_no',
        'news_stavanger_en',
        'news_stavanger_no',
        'news_trondheim_en',
        'news_trondheim_no',
        'shop_bergen_en',
        'shop_bergen_no',
        'shop_national_en',
        'shop_national_no',
        'shop_oslo_en',
        'shop_oslo_no',
        'shop_stavanger_en',
        'shop_stavanger_no',
        'shop_trondheim_en',
        'shop_trondheim_no',
      ]);
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
