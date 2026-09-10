import 'package:biso/data/services/device_subscription_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('round-trips the push target id', () async {
    final store = DeviceSubscriptionStore();
    expect(await store.readTargetId(), isNull);

    await store.writeTargetId('target-1');
    expect(await store.readTargetId(), 'target-1');
  });

  test('round-trips subscriber ids', () async {
    final store = DeviceSubscriptionStore();
    expect(await store.readSubscriberIds(), isEmpty);

    await store.writeTargetId('target-1');
    await store.setSubscriberIdIfAbsent(
      'news_oslo',
      'sub-1',
      targetId: 'target-1',
    );
    expect(await store.readSubscriberIds(), {'news_oslo': 'sub-1'});
  });

  test(
    'reads corrupt stored JSON as empty instead of throwing, so one bad write '
    'cannot brick notifications for the life of the install',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'topic_subscriber_ids': 'not json',
      });
      expect(await DeviceSubscriptionStore().readSubscriberIds(), isEmpty);
    },
  );

  test('ignores non-string values in stored JSON', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'topic_subscriber_ids': '{"news_oslo":"sub-1","events_oslo":42}',
    });
    expect(
      await DeviceSubscriptionStore().readSubscriberIds(),
      {'news_oslo': 'sub-1'},
    );
  });

  group('setSubscriberIdIfAbsent', () {
    test('adds one topic, leaving the others as they are', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'push_target_id': 'target-1',
        'topic_subscriber_ids': '{"general":"sub-1"}',
      });
      final store = DeviceSubscriptionStore();

      expect(
        await store.setSubscriberIdIfAbsent(
          'news_oslo',
          'sub-2',
          targetId: 'target-1',
        ),
        isTrue,
      );
      expect(await store.readSubscriberIds(), {
        'general': 'sub-1',
        'news_oslo': 'sub-2',
      });
    });

    test(
      'refuses when the stored target is not the one the subscriber was '
      'created on, or there is none, as after sign-out: the subscriber '
      'belongs to a target this device no longer uses',
      () async {
        final store = DeviceSubscriptionStore();
        expect(
          await store.setSubscriberIdIfAbsent(
            'news_oslo',
            'sub-1',
            targetId: 'target-1',
          ),
          isFalse,
          reason: 'no target stored',
        );

        await store.writeTargetId('target-2');
        expect(
          await store.setSubscriberIdIfAbsent(
            'news_oslo',
            'sub-1',
            targetId: 'target-1',
          ),
          isFalse,
          reason: 'a different target stored',
        );
        expect(await store.readSubscriberIds(), isEmpty);
      },
    );

    test(
      'refuses over an entry already recorded for the topic: it was recorded '
      'after this subscriber\'s request went out',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'push_target_id': 'target-1',
          'topic_subscriber_ids': '{"news_oslo":"sub-new"}',
        });
        final store = DeviceSubscriptionStore();

        expect(
          await store.setSubscriberIdIfAbsent(
            'news_oslo',
            'sub-late',
            targetId: 'target-1',
          ),
          isFalse,
        );
        expect(await store.readSubscriberIds(), {'news_oslo': 'sub-new'});
      },
    );

    test(
      'loses nothing when several changes are made at once: each reads the '
      'map and writes it back with nothing awaited in between, so none writes '
      'back a map read before another change landed',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'push_target_id': 'target-1',
          'topic_subscriber_ids': '{"events_oslo":"sub-0"}',
        });
        final store = DeviceSubscriptionStore();

        await Future.wait([
          store.setSubscriberIdIfAbsent(
            'general',
            'sub-1',
            targetId: 'target-1',
          ),
          store.removeSubscriberIdIfMatches('events_oslo', 'sub-0'),
          store.setSubscriberIdIfAbsent(
            'news_oslo',
            'sub-2',
            targetId: 'target-1',
          ),
        ]);

        expect(await store.readSubscriberIds(), {
          'general': 'sub-1',
          'news_oslo': 'sub-2',
        });
      },
    );
  });

  group('removeSubscriberIdIfMatches', () {
    test('forgets a topic still held by that subscriber, and only it', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'topic_subscriber_ids': '{"general":"sub-1","news_oslo":"sub-2"}',
      });
      final store = DeviceSubscriptionStore();

      expect(
        await store.removeSubscriberIdIfMatches('news_oslo', 'sub-2'),
        isTrue,
      );
      expect(await store.readSubscriberIds(), {'general': 'sub-1'});
    });

    test(
      'refuses when the topic now maps to a different subscriber: that one '
      'was recorded later, and is still live',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'topic_subscriber_ids': '{"news_oslo":"sub-new"}',
        });
        final store = DeviceSubscriptionStore();

        expect(
          await store.removeSubscriberIdIfMatches('news_oslo', 'sub-old'),
          isFalse,
        );
        expect(await store.readSubscriberIds(), {'news_oslo': 'sub-new'});
      },
    );
  });

  group('writeTargetId', () {
    test(
      'forgets the subscriber ids when it replaces a different target, in the '
      'same step: they belong to the old one',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'push_target_id': 'target-1',
          'topic_subscriber_ids': '{"news_oslo":"sub-1"}',
        });
        final store = DeviceSubscriptionStore();

        await store.writeTargetId('target-2');

        expect(await store.readTargetId(), 'target-2');
        expect(await store.readSubscriberIds(), isEmpty);
      },
    );

    test('keeps them when the target is unchanged', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'push_target_id': 'target-1',
        'topic_subscriber_ids': '{"news_oslo":"sub-1"}',
      });
      final store = DeviceSubscriptionStore();

      await store.writeTargetId('target-1');

      expect(await store.readSubscriberIds(), {'news_oslo': 'sub-1'});
    });
  });

  test('round-trips a pending token invalidation', () async {
    final store = DeviceSubscriptionStore();
    expect(await store.readPendingTokenInvalidation(), isFalse);

    await store.writePendingTokenInvalidation();
    expect(await store.readPendingTokenInvalidation(), isTrue);
  });

  test(
    'clear removes every key, a pending token invalidation included - it is '
    'only ever cleared once the device is known to be detached',
    () async {
      final store = DeviceSubscriptionStore();
      await store.writeTargetId('target-1');
      await store.setSubscriberIdIfAbsent(
        'news_oslo',
        'sub-1',
        targetId: 'target-1',
      );
      await store.writePendingTokenInvalidation();

      await store.clear();

      expect(await store.readTargetId(), isNull);
      expect(await store.readSubscriberIds(), isEmpty);
      expect(await store.readPendingTokenInvalidation(), isFalse);
    },
  );
}
