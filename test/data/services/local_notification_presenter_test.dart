import 'dart:convert';
import 'dart:io';

import 'package:biso/data/services/local_notification_presenter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _launchTests();
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
    expect(kNotificationIcon, '@mipmap/launcher_icon');
    expect(
      File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync().contains(kNotificationIcon),
      isTrue,
    );
    expect(
      File(
        'android/app/src/main/res/raw/keep.xml',
      ).readAsStringSync().contains('tools:keep="$kNotificationIcon"'),
      isTrue,
    );
  });
}
