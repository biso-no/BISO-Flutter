import 'package:biso/core/constants/notification_topics.dart';
import 'package:biso/data/services/notification_inbox_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isTopicAudienceVisible', () {
    test(
      'hides a campus-scoped announcement when the student has turned that '
      'logical topic off - this is the case that regressed: audience_value '
      'is now "events_oslo", not the bare "events" the old lookup expected',
      () {
        expect(
          isTopicAudienceVisible('events_oslo', {
            'events': false,
          }, campusId: '1'),
          isFalse,
        );
      },
    );

    test('shows a campus-scoped announcement for the student\'s own campus '
        'when the topic is on', () {
      expect(
        isTopicAudienceVisible('events_oslo', {'events': true}, campusId: '1'),
        isTrue,
      );
    });

    test('hides an announcement scoped to a campus other than the student\'s '
        'own, even though the topic itself is on - this is the bug: push '
        'delivery is campus-scoped, so an Oslo student was never pushed a '
        'Bergen announcement, but the old campus-blind lookup showed it to '
        'them anyway', () {
      expect(
        isTopicAudienceVisible('events_bergen', {
          'events': true,
        }, campusId: '1'),
        isFalse,
      );
    });

    test('a national-scoped announcement is governed by the same logical topic '
        'as its campus-scoped sibling', () {
      expect(
        isTopicAudienceVisible('news_national', {'news': false}, campusId: '1'),
        isFalse,
      );
      expect(
        isTopicAudienceVisible('news_$kNationalSlug', {
          'news': true,
        }, campusId: '1'),
        isTrue,
      );
    });

    test('a topic switched off is hidden both for the student\'s own campus '
        'scope and the national scope', () {
      expect(
        isTopicAudienceVisible('events_oslo', {'events': false}, campusId: '1'),
        isFalse,
      );
      expect(
        isTopicAudienceVisible('events_national', {
          'events': false,
        }, campusId: '1'),
        isFalse,
      );
    });

    test(
      'the general topic is always visible regardless of intent or campus',
      () {
        expect(
          isTopicAudienceVisible(kGeneralTopicId, {}, campusId: '1'),
          isTrue,
        );
        expect(
          isTopicAudienceVisible(kGeneralTopicId, {
            'news': false,
            'events': false,
            'jobs': false,
            'shop': false,
          }, campusId: null),
          isTrue,
        );
      },
    );

    test('defaults to visible for a topic absent from the intent map, matching '
        "reconcile()'s own default-on behaviour for a topic the student has "
        'never toggled', () {
      expect(isTopicAudienceVisible('jobs_bergen', {}, campusId: '2'), isTrue);
    });

    test('defaults to visible for an unrecognised audience value rather than '
        'hiding it outright', () {
      expect(
        isTopicAudienceVisible('mystery_topic_oslo', {
          'events': false,
        }, campusId: '1'),
        isTrue,
      );
    });

    test('a bare legacy audience value - written before campus scoping existed '
        '- stays visible even when the student has switched that topic off, '
        'covering historical announcements that predate this branch', () {
      expect(
        isTopicAudienceVisible('events', {'events': false}, campusId: '1'),
        isTrue,
      );
    });

    test('covers every logical topic, not just events', () {
      for (final topic in NotificationTopic.values) {
        expect(
          isTopicAudienceVisible('${topic.id}_stavanger', {
            topic.id: false,
          }, campusId: '4'),
          isFalse,
          reason: '${topic.id} should be hidden when switched off',
        );
      }
    });

    test('a National-campus student (id "5") sees only national scope, not an '
        'arbitrary other campus - their own-campus scope and the national '
        'scope collapse to the same slug', () {
      expect(
        isTopicAudienceVisible('events_oslo', {'events': true}, campusId: '5'),
        isFalse,
        reason: 'not their campus',
      );
      expect(
        isTopicAudienceVisible('events_national', {
          'events': true,
        }, campusId: '5'),
        isTrue,
      );
    });

    test('a student with no profile campus (null) is treated the same as '
        'National, since campusSlugFor falls back to the national slug either '
        'way', () {
      expect(
        isTopicAudienceVisible('events_oslo', {'events': true}, campusId: null),
        isFalse,
        reason: 'not their campus',
      );
      expect(
        isTopicAudienceVisible('events_national', {
          'events': true,
        }, campusId: null),
        isTrue,
      );
    });
  });
}
