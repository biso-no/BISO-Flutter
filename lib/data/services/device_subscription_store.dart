import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local record of this install's push subscriptions.
///
/// An Appwrite push target belongs to a *device*, not to a user, and the client
/// SDK offers no way to list a topic's subscribers — so the subscriber ids
/// needed to unsubscribe have nowhere to live but here. Account preferences
/// would be wrong: two devices sharing one account would overwrite each other,
/// and unsubscribing on one would delete the other's subscription.
///
/// The student's *intent* is per-user and lives in account preferences instead.
class DeviceSubscriptionStore {
  static const String _targetKey = 'push_target_id';
  static const String _subscribersKey = 'topic_subscriber_ids';
  static const String _pendingInvalidationKey = 'pending_token_invalidation';

  Future<String?> readTargetId() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_targetKey);
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> writeTargetId(String targetId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_targetKey, targetId);
  }

  /// The `topicId -> Appwrite subscriber $id` map for this device.
  ///
  /// Unreadable or malformed storage reads as empty rather than throwing. A
  /// device that cannot read its map re-creates its subscriptions on the next
  /// reconcile, which is recoverable; an exception here would break
  /// notifications for the life of the install.
  Future<Map<String, String>> readSubscriberIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_subscribersKey);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return <String, String>{
        for (final entry in decoded.entries)
          if (entry.value is String) entry.key.toString(): entry.value as String,
      };
    } catch (e) {
      debugPrint('DeviceSubscriptionStore: unreadable subscriber ids: $e');
      return <String, String>{};
    }
  }

  Future<void> writeSubscriberIds(Map<String, String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_subscribersKey, jsonEncode(ids));
  }

  /// Whether a sign-out left this device's FCM token still valid, and possibly
  /// still bound to the signed-out account's push target.
  ///
  /// Device-local, and read on every launch: nothing else remembers that the
  /// token must be invalidated before this device may register a push target
  /// again. See `NotificationService.clearToken`.
  Future<bool> readPendingTokenInvalidation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pendingInvalidationKey) ?? false;
  }

  Future<void> writePendingTokenInvalidation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pendingInvalidationKey, true);
  }

  /// Forgets everything this store holds.
  ///
  /// Every key is removed in one synchronous step, before anything is awaited:
  /// a caller that checked it may still write (see `NotificationService`'s
  /// queue) has then made the whole change, instead of leaving later removals
  /// to land after it may have lost that right.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_targetKey),
      prefs.remove(_subscribersKey),
      prefs.remove(_pendingInvalidationKey),
    ]);
  }
}
