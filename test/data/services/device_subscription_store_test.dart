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

    await store.writeSubscriberIds({'news_oslo': 'sub-1'});
    expect(await store.readSubscriberIds(), {'news_oslo': 'sub-1'});
  });

  test('replaces the stored map wholesale rather than merging', () async {
    final store = DeviceSubscriptionStore();
    await store.writeSubscriberIds({'news_oslo': 'sub-1'});
    await store.writeSubscriberIds({'events_oslo': 'sub-2'});
    expect(await store.readSubscriberIds(), {'events_oslo': 'sub-2'});
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
      await store.writeSubscriberIds({'news_oslo': 'sub-1'});
      await store.writePendingTokenInvalidation();

      await store.clear();

      expect(await store.readTargetId(), isNull);
      expect(await store.readSubscriberIds(), isEmpty);
      expect(await store.readPendingTokenInvalidation(), isFalse);
    },
  );
}
