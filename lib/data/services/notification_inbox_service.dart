import 'dart:async';

import 'package:appwrite/appwrite.dart';

import '../../core/constants/app_constants.dart';
import '../models/app_notification_model.dart';
import 'appwrite_service.dart';

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
  Future<List<AppNotification>> fetchInbox({
    required String userId,
    required String locale,
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

      // 2. Broadcast feed: sent announcements addressed to everyone.
      final broadcastRows = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: _announcementsTable,
        queries: [
          Query.equal('status', 'sent'),
          Query.equal('audience_type', ['topic', 'broadcast']),
          Query.orderDesc('sent_at'),
          Query.limit(_fetchLimit),
        ],
      );

      final announcementById = <String, Map<String, dynamic>>{};
      for (final row in broadcastRows.rows) {
        announcementById[row.$id] = row.data;
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
          announcementById[row.$id] = row.data;
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
