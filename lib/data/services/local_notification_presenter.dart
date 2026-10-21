import 'dart:convert';
import 'dart:ui' show Color, Locale;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../generated/l10n/app_localizations.dart';

/// Android channel for ordinary pushes. Also named in the manifest as
/// Firebase's default channel.
const String kDefaultChannelId = 'biso_default';

/// Android channel for pushes with `category == 'urgent'`.
const String kUrgentChannelId = 'biso_urgent';

/// The notification small icon: a monochrome vector, as the Android status bar
/// requires. Also named in the manifest as Firebase's default icon; kept from
/// resource shrinking by `res/raw/keep.xml`.
const String kNotificationIcon = '@drawable/ic_stat_biso';

/// Accent colour of the small icon (the logo blue), matching
/// `notification_accent` in `res/values/colors.xml`.
const Color kNotificationColor = Color(0xFF3D9BE0);

const int _fnvOffsetBasis = 0x811c9dc5;
const int _fnvPrime = 0x01000193;
const int _mask32 = 0xffffffff;
const int _mask31 = 0x7fffffff;

/// A notification id derived from the push, so a re-delivered push replaces its
/// earlier notification instead of showing twice, and ids survive restarts.
/// Null when the push carries neither an `announcement_id` nor a message id.
@visibleForTesting
int? notificationIdFor(Map<String, dynamic> data, String? messageId) {
  final announcementId = data['announcement_id'];
  final key = announcementId is String && announcementId.isNotEmpty
      ? 'a:$announcementId'
      : (messageId != null && messageId.isNotEmpty ? 'm:$messageId' : null);
  if (key == null) return null;
  // FNV-1a, 32 bit. String.hashCode is not stable across runs.
  var hash = _fnvOffsetBasis;
  for (final unit in utf8.encode(key)) {
    hash = ((hash ^ unit) * _fnvPrime) & _mask32;
  }
  return hash & _mask31;
}

/// Decodes a notification payload (`jsonEncode(message.data)`), or null when
/// it is absent or not a JSON object.
@visibleForTesting
Map<String, dynamic>? decodeNotificationPayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final decoded = jsonDecode(payload);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } on FormatException catch (e) {
    debugPrint('Ignoring malformed notification payload: $e');
    return null;
  }
}

/// Passes on the payload of the notification whose tap launched the app, if
/// any. The plugin only reports taps while the app runs; a tap that starts a
/// killed app is only visible through its launch details.
@visibleForTesting
Future<void> deliverLaunchTap(
  Future<NotificationAppLaunchDetails?> Function() lookup,
  void Function(Map<String, dynamic> data) onTap,
) async {
  final details = await lookup();
  if (details == null || !details.didNotificationLaunchApp) return;
  final data = decodeNotificationPayload(details.notificationResponse?.payload);
  if (data != null) onTap(data);
}

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

  /// Names the channels in [languageCode] ('en' or 'no').
  Future<void> setLanguage(String languageCode);
}

class FlutterLocalNotificationsPresenter implements LocalNotificationPresenter {
  FlutterLocalNotificationsPresenter([
    FlutterLocalNotificationsPlugin? plugin,
    Future<NotificationAppLaunchDetails?> Function()? launchDetails,
  ]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _launchDetails = launchDetails;

  final Future<NotificationAppLaunchDetails?> Function()? _launchDetails;

  final FlutterLocalNotificationsPlugin _plugin;
  int _nextId = 0;

  String _languageCode = 'en';

  AndroidNotificationChannel get _defaultChannel => AndroidNotificationChannel(
    kDefaultChannelId,
    lookupAppLocalizations(Locale(_languageCode)).notificationChannelDefault,
    importance: Importance.defaultImportance,
  );

  AndroidNotificationChannel get _urgentChannel => AndroidNotificationChannel(
    kUrgentChannelId,
    lookupAppLocalizations(Locale(_languageCode)).notificationChannelUrgent,
    importance: Importance.high,
  );

  @override
  Future<void> setLanguage(String languageCode) async {
    _languageCode = languageCode;
    await _createChannels();
  }

  Future<void> _createChannels() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    // Creating a channel again with the same id renames it.
    await android?.createNotificationChannel(_defaultChannel);
    await android?.createNotificationChannel(_urgentChannel);
  }

  @override
  Future<void> initialize({
    required void Function(Map<String, dynamic> data) onTap,
  }) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(kNotificationIcon),
      ),
      onDidReceiveNotificationResponse: (response) {
        final data = decodeNotificationPayload(response.payload);
        if (data != null) onTap(data);
      },
    );
    await _createChannels();
    await deliverLaunchTap(
      _launchDetails ?? _plugin.getNotificationAppLaunchDetails,
      onTap,
    );
  }

  @override
  Future<void> show(RemoteMessage message) async {
    final data = message.data;
    final title = message.notification?.title ?? data['title'] as String?;
    final body = message.notification?.body ?? data['body'] as String?;
    final channelId = channelIdFor(data);
    final isUrgent = channelId == kUrgentChannelId;
    await _plugin.show(
      id: notificationIdFor(data, message.messageId) ?? _nextId++,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          isUrgent ? _urgentChannel.name : _defaultChannel.name,
          importance: isUrgent ? Importance.high : Importance.defaultImportance,
          priority: isUrgent ? Priority.high : Priority.defaultPriority,
          icon: kNotificationIcon,
          color: kNotificationColor,
        ),
      ),
      payload: jsonEncode(data),
    );
  }
}
