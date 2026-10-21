import 'dart:convert';
import 'dart:io';

import 'package:biso/data/services/local_notification_presenter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _launchTests();
  group('notificationIdFor', () {
    test('is stable for the same announcement id', () {
      final a = notificationIdFor({'announcement_id': 'abc'}, 'm1');
      expect(a, notificationIdFor({'announcement_id': 'abc'}, 'm2'));
    });

    test('differs for different ids and stays within 31 bits', () {
      final ids = {
        for (var i = 0; i < 200; i++)
          notificationIdFor({'announcement_id': 'id-$i'}, null),
      };
      expect(ids.length, 200);
      for (final id in ids) {
        expect(id, isNotNull);
        expect(id! >= 0 && id < 0x80000000, isTrue);
      }
    });

    test('falls back to the message id, then null', () {
      expect(notificationIdFor({}, 'm1'), isNotNull);
      expect(notificationIdFor({}, 'm1'), notificationIdFor({}, 'm1'));
      expect(notificationIdFor({}, 'm1'), isNot(notificationIdFor({}, 'm2')));
      expect(notificationIdFor({}, null), isNull);
      expect(notificationIdFor({'announcement_id': ''}, null), isNull);
    });
  });

  group('setLanguage', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final created = <String>[];

    setUp(() {
      created.clear();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'createNotificationChannel') {
              created.add((call.arguments as Map)['name'] as String);
            }
            return null;
          });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('names the channels in Norwegian', () async {
      await FlutterLocalNotificationsPresenter().setLanguage('no');
      expect(created, ['BISO', 'Viktig fra BISO']);
    });

    test('names the channels in English', () async {
      await FlutterLocalNotificationsPresenter().setLanguage('en');
      expect(created, ['BISO', 'Urgent from BISO']);
    });
  });

  group('channelIdFor', () {
    test('urgent pushes use the urgent channel', () {
      expect(
        channelIdFor(<String, dynamic>{'category': 'urgent'}),
        kUrgentChannelId,
      );
      expect(kUrgentChannelId, 'biso_urgent');
    });

    test('every other push uses the default channel', () {
      expect(
        channelIdFor(<String, dynamic>{'category': 'event'}),
        kDefaultChannelId,
      );
      expect(channelIdFor(<String, dynamic>{}), kDefaultChannelId);
      expect(kDefaultChannelId, 'biso_default');
    });
  });
}

void _launchTests() {
  group('deliverLaunchTap', () {
    NotificationAppLaunchDetails launched(String? payload) =>
        NotificationAppLaunchDetails(
          true,
          notificationResponse: NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: payload,
          ),
        );

    test(
      'passes on the payload of the tap that launched the app once',
      () async {
        final taps = <Map<String, dynamic>>[];
        await deliverLaunchTap(
          () async => launched(jsonEncode({'deep_link': 'biso://news?id=n1'})),
          taps.add,
        );
        expect(taps, [
          {'deep_link': 'biso://news?id=n1'},
        ]);
      },
    );

    test('ignores invalid, missing, and non-launch details', () async {
      final taps = <Map<String, dynamic>>[];
      await deliverLaunchTap(() async => launched('{not json'), taps.add);
      await deliverLaunchTap(() async => launched(null), taps.add);
      await deliverLaunchTap(() async => launched('[1]'), taps.add);
      await deliverLaunchTap(
        () async => const NotificationAppLaunchDetails(false),
        taps.add,
      );
      await deliverLaunchTap(() async => null, taps.add);
      expect(taps, isEmpty);
    });
  });

  test('the small icon is one the manifest uses and keep.xml protects', () {
    expect(kNotificationIcon, '@drawable/ic_stat_biso');
    expect(
      File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync().contains(kNotificationIcon),
      isTrue,
    );
    expect(
      File(
        'android/app/src/main/res/raw/keep.xml',
      ).readAsStringSync().contains(kNotificationIcon),
      isTrue,
    );
  });
}
