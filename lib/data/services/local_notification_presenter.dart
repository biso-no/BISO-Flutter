import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Android channel for ordinary pushes. Also named in the manifest as
/// Firebase's default channel.
const String kDefaultChannelId = 'biso_default';

/// Android channel for pushes with `category == 'urgent'`.
const String kUrgentChannelId = 'biso_urgent';

/// The channel a push with [data] belongs on.
@visibleForTesting
String channelIdFor(Map<String, dynamic> data) =>
    data['category'] == 'urgent' ? kUrgentChannelId : kDefaultChannelId;

/// Shows a push as a system notification while the app is in the foreground.
///
/// Android does not present foreground FCM messages itself; iOS does.
abstract class LocalNotificationPresenter {
  /// Creates the channels and routes taps on a shown notification to [onTap]
  /// with the push's data.
  Future<void> initialize({
    required void Function(Map<String, dynamic> data) onTap,
  });

  Future<void> show(RemoteMessage message);
}

class FlutterLocalNotificationsPresenter implements LocalNotificationPresenter {
  FlutterLocalNotificationsPresenter([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  int _nextId = 0;

  static const _defaultChannel = AndroidNotificationChannel(
    kDefaultChannelId,
    'BISO',
    importance: Importance.defaultImportance,
  );
  static const _urgentChannel = AndroidNotificationChannel(
    kUrgentChannelId,
    'Urgent from BISO',
    importance: Importance.high,
  );

  @override
  Future<void> initialize({
    required void Function(Map<String, dynamic> data) onTap,
  }) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map) onTap(Map<String, dynamic>.from(decoded));
        } on FormatException catch (e) {
          debugPrint('Ignoring malformed notification payload: $e');
        }
      },
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(_defaultChannel);
    await android?.createNotificationChannel(_urgentChannel);
  }

  @override
  Future<void> show(RemoteMessage message) async {
    final data = message.data;
    final title = message.notification?.title ?? data['title'] as String?;
    final body = message.notification?.body ?? data['body'] as String?;
    final channelId = channelIdFor(data);
    final isUrgent = channelId == kUrgentChannelId;
    await _plugin.show(
      id: _nextId++,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          isUrgent ? _urgentChannel.name : _defaultChannel.name,
          importance: isUrgent ? Importance.high : Importance.defaultImportance,
          priority: isUrgent ? Priority.high : Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: jsonEncode(data),
    );
  }
}
