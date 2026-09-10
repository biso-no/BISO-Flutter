import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/notification_topics.dart';
import '../models/app_notification_model.dart';
import 'appwrite_service.dart';

/// Whether a `topic` announcement addressed to Appwrite topic id
/// [audienceValue] should appear in a student's inbox, given their logical
/// [topicIntent] (as returned by `NotificationService.loadTopicIntent()`).
///
/// [audienceValue] is a campus-scoped id such as `events_oslo` or
/// `events_national` — never the bare logical topic — except for
/// [kGeneralTopicId], which every device holds unconditionally and so is
/// always visible. The campus suffix is stripped to recover the logical topic
/// ([NotificationTopic.id]) before consulting [topicIntent], because intent is
/// per-topic, not per-campus: `events_oslo` must be hidden by the same switch
/// that hides `events_national`. A topic absent from [topicIntent], or an
/// audience value that matches no known topic, defaults to visible — the same
/// default `reconcile()` applies to a topic the student has never toggled.
///
/// Extracted as a top-level, `@visibleForTesting` function (rather than kept
/// as a private instance method) following the pattern
/// `decodeTopicSubscriptions` uses in `notification_service.dart`.
@visibleForTesting
bool isTopicAudienceVisible(String audienceValue, Map<String, bool> topicIntent) {
  if (audienceValue == kGeneralTopicId) return true;
  for (final topic in NotificationTopic.values) {
    if (audienceValue.startsWith('${topic.id}_')) {
      return topicIntent[topic.id] != false;
    }
  }
  return true;
}

/// Reads/writes the in-app notification inbox backed by the Appwrite
/// `announcements` and `user_notifications` collections in database `app`.
///
/// Uses the shared [db] (`TablesDB`) and [realtime] singletons from
/// [appwrite_service.dart], mirroring [ChatService].
class NotificationInboxService {
  static const String _announcementsTable = 'announcements';
  static const String _userNotificationsTable = 'user_notifications';
  static const int _fetchLimit = 50;

  // Appwrite Query.equal('$id', [...]) supports a bounded list; chunk to stay
  // within reasonable request sizes.
  static const int _idChunkSize = 25;

  Realtime get _realtime => realtime;

  String get _announcementsChannel => Channel.tablesdb(
    AppConstants.databaseId,
  ).table(_announcementsTable).row().toString();

  String get _userNotificationsChannel => Channel.tablesdb(
    AppConstants.databaseId,
  ).table(_userNotificationsTable).row().toString();

  /// Fetch the merged inbox for [userId] localized to [locale].
  ///
  /// [topicIntent] is the student's logical topic intent — `news`/`events`/
  /// `jobs`/`shop` — as returned by `NotificationService.loadTopicIntent()`.
  /// Broadcast announcements always appear; a `topic` announcement (whose
  /// `audience_value` is a campus-scoped Appwrite topic id, e.g. `events_oslo`)
  /// is shown only when the student hasn't explicitly opted out of that
  /// topic's logical intent (default-show when the topic is absent from the
  /// map — see [isTopicAudienceVisible]).
  Future<List<AppNotification>> fetchInbox({
    required String userId,
    required String locale,
    Map<String, bool> topicIntent = const {},
  }) async {
    try {
      // 1. Targeted notifications for this user (read state + row id).
      final userRows = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: _userNotificationsTable,
        queries: [
          Query.equal('user_id', userId),
          Query.orderDesc('\$createdAt'),
          Query.limit(_fetchLimit),
        ],
      );

      final readByAnnouncement = <String, bool>{};
      final userNotificationIdByAnnouncement = <String, String>{};
      for (final row in userRows.rows) {
        final announcementId = row.data['announcement_id'] as String?;
        if (announcementId == null || announcementId.isEmpty) continue;
        readByAnnouncement[announcementId] = row.data['read'] == true;
        userNotificationIdByAnnouncement[announcementId] = row.$id;
      }

      // 2. Broadcast feed: sent announcements addressed to everyone. Query
      // broadcasts and topics separately, each with its own limit, so a busy
      // topic backlog can't push broadcasts out of the limited result set.
      final broadcastRows = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: _announcementsTable,
        queries: [
          Query.equal('status', 'sent'),
          Query.equal('audience_type', 'broadcast'),
          Query.orderDesc('sent_at'),
          Query.limit(_fetchLimit),
        ],
      );
      final topicRows = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: _announcementsTable,
        queries: [
          Query.equal('status', 'sent'),
          Query.equal('audience_type', 'topic'),
          Query.orderDesc('sent_at'),
          Query.limit(_fetchLimit),
        ],
      );

      final announcementById = <String, Map<String, dynamic>>{};
      for (final row in broadcastRows.rows) {
        announcementById[row.$id] = _rowToMap(row);
      }
      for (final row in topicRows.rows) {
        // Hide topic announcements the user has opted out of.
        if (!_isTopicVisible(row.data, topicIntent)) continue;
        announcementById[row.$id] = _rowToMap(row);
      }

      // 3. Fetch any targeted announcements not already in the broadcast feed.
      final missingIds = userNotificationIdByAnnouncement.keys
          .where((id) => !announcementById.containsKey(id))
          .toList();
      for (final chunk in _chunk(missingIds, _idChunkSize)) {
        if (chunk.isEmpty) continue;
        final rows = await db.listRows(
          databaseId: AppConstants.databaseId,
          tableId: _announcementsTable,
          queries: [
            Query.equal('\$id', chunk),
            Query.limit(chunk.length),
          ],
        );
        for (final row in rows.rows) {
          announcementById[row.$id] = _rowToMap(row);
        }
      }

      // 4. Merge unique by announcement id and build the localized list.
      final items = announcementById.entries.map((entry) {
        return AppNotification.fromAnnouncement(
          entry.value,
          locale: locale,
          read: readByAnnouncement[entry.key] ?? false,
          userNotificationId: userNotificationIdByAnnouncement[entry.key],
        );
      }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return items;
    } on AppwriteException catch (e) {
      throw NotificationInboxException('Failed to load inbox: ${e.message}');
    } catch (e) {
      throw NotificationInboxException('Failed to load inbox: $e');
    }
  }

  /// Fetch a single announcement by [announcementId] localized to [locale].
  ///
  /// When [userId] is provided, also looks up the matching `user_notifications`
  /// row so the returned [AppNotification] carries the per-user read state and
  /// its row `$id`. Returns `null` when the announcement does not exist.
  Future<AppNotification?> fetchAnnouncementById({
    required String announcementId,
    required String locale,
    String? userId,
  }) async {
    try {
      final announcementRows = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: _announcementsTable,
        queries: [
          Query.equal('\$id', announcementId),
          Query.limit(1),
        ],
      );

      if (announcementRows.rows.isEmpty) {
        return null;
      }

      final doc = _rowToMap(announcementRows.rows.first);

      bool read = false;
      String? userNotificationId;

      if (userId != null && userId.isNotEmpty) {
        final userRows = await db.listRows(
          databaseId: AppConstants.databaseId,
          tableId: _userNotificationsTable,
          queries: [
            Query.equal('user_id', userId),
            Query.equal('announcement_id', announcementId),
            Query.limit(1),
          ],
        );

        if (userRows.rows.isNotEmpty) {
          final row = userRows.rows.first;
          read = row.data['read'] == true;
          userNotificationId = row.$id;
        }
      }

      return AppNotification.fromAnnouncement(
        doc,
        locale: locale,
        read: read,
        userNotificationId: userNotificationId,
      );
    } on AppwriteException catch (e) {
      throw NotificationInboxException(
        'Failed to load announcement: ${e.message}',
      );
    } catch (e) {
      throw NotificationInboxException('Failed to load announcement: $e');
    }
  }

  /// Mark [notification] as read for [userId].
  ///
  /// Updates the existing `user_notifications` row when present, otherwise
  /// creates one scoped to the user with row-level read/update/delete
  /// permissions.
  Future<void> markAsRead(
    AppNotification notification, {
    required String userId,
  }) async {
    try {
      if (notification.userNotificationId != null) {
        await db.updateRow(
          databaseId: AppConstants.databaseId,
          tableId: _userNotificationsTable,
          rowId: notification.userNotificationId!,
          data: {'read': true},
        );
        return;
      }

      await db.createRow(
        databaseId: AppConstants.databaseId,
        tableId: _userNotificationsTable,
        rowId: ID.unique(),
        data: {
          'user_id': userId,
          'announcement_id': notification.id,
          'read': true,
        },
        permissions: [
          Permission.read(Role.user(userId)),
          Permission.update(Role.user(userId)),
          Permission.delete(Role.user(userId)),
        ],
      );
    } on AppwriteException catch (e) {
      throw NotificationInboxException('Failed to mark as read: ${e.message}');
    } catch (e) {
      throw NotificationInboxException('Failed to mark as read: $e');
    }
  }

  /// Subscribe to realtime changes on the announcements + user notifications
  /// collections so the provider can refresh the inbox. Mirrors
  /// [ChatService.subscribeToUpdates].
  RealtimeSubscription subscribe({required void Function() onChange}) {
    final subscription = _realtime.subscribe([
      _announcementsChannel,
      _userNotificationsChannel,
    ]);

    subscription.stream.listen((_) {
      onChange();
    });

    return subscription;
  }

  /// Appwrite's `row.data` doesn't carry the system fields, but the model needs
  /// `$id` (and `$createdAt` for ordering). Merge them back in before building
  /// an [AppNotification] so broadcast items get a real id (for tap → detail
  /// and mark-as-read), not an empty string.
  Map<String, dynamic> _rowToMap(dynamic row) {
    final data = Map<String, dynamic>.from(row.data as Map);
    data['\$id'] = row.$id;
    data['\$createdAt'] = row.$createdAt;
    return data;
  }

  /// A `topic` announcement is visible only when the user is subscribed to its
  /// topic; broadcasts (and any non-topic audience) are always visible.
  bool _isTopicVisible(
    Map<String, dynamic> data,
    Map<String, bool> topicIntent,
  ) {
    if (data['audience_type'] != 'topic') return true;
    final audienceValue = data['audience_value'] as String?;
    if (audienceValue == null || audienceValue.isEmpty) return true;
    return isTopicAudienceVisible(audienceValue, topicIntent);
  }

  Iterable<List<T>> _chunk<T>(List<T> source, int size) sync* {
    for (var i = 0; i < source.length; i += size) {
      yield source.sublist(i, i + size > source.length ? source.length : i + size);
    }
  }
}

class NotificationInboxException implements Exception {
  final String message;
  NotificationInboxException(this.message);

  @override
  String toString() => message;
}
