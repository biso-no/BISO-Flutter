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

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_targetKey);
    await prefs.remove(_subscribersKey);
  }
}
