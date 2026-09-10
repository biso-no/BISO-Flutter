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
///
/// The subscriber ids change one topic at a time, never by writing a whole map
/// back. The answer to a subscribe or unsubscribe can arrive after the run that
/// sent it was abandoned, while a later run records changes of its own (see
/// `NotificationService._reconcileNow`), and a whole map written back by
/// either would erase what the other recorded in between. Each change reads
/// the map and writes it back with nothing awaited in between: the
/// `SharedPreferences` instance is obtained first, and it updates its
/// in-memory cache synchronously when a value is set or removed, so no other
/// code can run between the read and the write.
class DeviceSubscriptionStore {
  static const String _targetKey = 'push_target_id';
  static const String _subscribersKey = 'topic_subscriber_ids';
  static const String _pendingInvalidationKey = 'pending_token_invalidation';

  Future<String?> readTargetId() async {
    final prefs = await SharedPreferences.getInstance();
    return _targetIdIn(prefs);
  }

  /// Records [targetId] as this device's push target.
  ///
  /// A subscriber belongs to a target, so when [targetId] replaces a different
  /// stored target the subscriber ids are forgotten in the same step. Nothing
  /// can be recorded against the old target between the two writes, and so
  /// survive into the new one.
  Future<void> writeTargetId(String targetId) async {
    final prefs = await SharedPreferences.getInstance();
    final previous = _targetIdIn(prefs);
    await Future.wait([
      prefs.setString(_targetKey, targetId),
      if (previous != null && previous != targetId)
        prefs.remove(_subscribersKey),
    ]);
  }

  /// The `topicId -> Appwrite subscriber $id` map for this device.
  ///
  /// Unreadable or malformed storage reads as empty rather than throwing. A
  /// device that cannot read its map re-creates its subscriptions on the next
  /// reconcile, which is recoverable; an exception here would break
  /// notifications for the life of the install.
  Future<Map<String, String>> readSubscriberIds() async {
    final prefs = await SharedPreferences.getInstance();
    return _subscriberIdsIn(prefs);
  }

  /// Records that [subscriberId] holds [topicId] on this device, reporting
  /// whether it did.
  ///
  /// Only while [targetId], the target the subscriber was created on, is still
  /// the stored target, and nothing is recorded for [topicId] yet. Once
  /// sign-out has cleared this store, or the target has changed, the
  /// subscriber belongs to a target this device no longer uses — possibly
  /// another account's — and an entry for it would claim a topic is held when
  /// it is not. An entry already there was recorded after this subscriber's
  /// request went out.
  Future<bool> setSubscriberIdIfAbsent(
    String topicId,
    String subscriberId, {
    required String targetId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // Nothing is awaited from here until the write has been made.
    if (_targetIdIn(prefs) != targetId) return false;
    final ids = _subscriberIdsIn(prefs);
    if (ids.containsKey(topicId)) return false;
    ids[topicId] = subscriberId;
    await prefs.setString(_subscribersKey, jsonEncode(ids));
    return true;
  }

  /// Forgets [topicId]'s subscriber, but only while it is still
  /// [subscriberId], reporting whether it did.
  ///
  /// An entry that has changed since was recorded for a later subscriber,
  /// which is still live: forgetting it would leave that subscriber with no id
  /// on this device.
  Future<bool> removeSubscriberIdIfMatches(
    String topicId,
    String subscriberId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    // Nothing is awaited from here until the write has been made.
    final ids = _subscriberIdsIn(prefs);
    if (ids[topicId] != subscriberId) return false;
    ids.remove(topicId);
    await prefs.setString(_subscribersKey, jsonEncode(ids));
    return true;
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

  static String? _targetIdIn(SharedPreferences prefs) {
    final value = prefs.getString(_targetKey);
    return (value == null || value.isEmpty) ? null : value;
  }

  static Map<String, String> _subscriberIdsIn(SharedPreferences prefs) {
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
}
