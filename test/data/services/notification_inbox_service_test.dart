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
          isTopicAudienceVisible('events_oslo', {'events': false}),
          isFalse,
        );
      },
    );

    test('shows a campus-scoped announcement when the topic is on', () {
      expect(isTopicAudienceVisible('events_oslo', {'events': true}), isTrue);
    });

    test('a national-scoped announcement is governed by the same logical topic '
        'as its campus-scoped sibling', () {
      expect(isTopicAudienceVisible('news_national', {'news': false}), isFalse);
      expect(
        isTopicAudienceVisible('news_$kNationalSlug', {'news': true}),
        isTrue,
      );
    });

    test('the general topic is always visible regardless of intent', () {
      expect(isTopicAudienceVisible(kGeneralTopicId, {}), isTrue);
      expect(
        isTopicAudienceVisible(kGeneralTopicId, {
          'news': false,
          'events': false,
          'jobs': false,
          'shop': false,
        }),
        isTrue,
      );
    });

    test('defaults to visible for a topic absent from the intent map, matching '
        "reconcile()'s own default-on behaviour for a topic the student has "
        'never toggled', () {
      expect(isTopicAudienceVisible('jobs_bergen', {}), isTrue);
    });

    test('defaults to visible for an unrecognised audience value rather than '
        'hiding it outright', () {
      expect(
        isTopicAudienceVisible('mystery_topic_oslo', {'events': false}),
        isTrue,
      );
    });

    test('covers every logical topic, not just events', () {
      for (final topic in NotificationTopic.values) {
        expect(
          isTopicAudienceVisible('${topic.id}_stavanger', {topic.id: false}),
          isFalse,
          reason: '${topic.id} should be hidden when switched off',
        );
      }
    });
  });
}
