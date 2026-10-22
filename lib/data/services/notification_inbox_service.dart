import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/notification_topics.dart';
import '../models/app_notification_model.dart';
import 'appwrite_service.dart';
import 'notifications_api_client.dart';

/// Whether a `topic` announcement addressed to Appwrite topic id
/// [audienceValue] should appear in a student's inbox, given their logical
/// [topicIntent] (as returned by `NotificationService.loadTopicIntent()`) and
/// their profile (home) campus [campusId].
///
/// [audienceValue] is a campus-scoped id such as `events_oslo` or
/// `events_national` — never the bare logical topic — except for
/// [kGeneralTopicId], which every device holds unconditionally and so is
/// always visible, and except for historical rows written before campus
/// scoping existed, whose `audience_value` is a bare logical topic such as
/// `events`.
///
/// Push delivery is campus-scoped: a device only ever holds a subscription
/// for [campusId]'s own scope (via [campusSlugFor]) and the national scope —
/// see `NotificationService.reconcile()`. The inbox must draw the same line,
/// or a student sees announcements addressed to campuses they were never
/// pushed to. So a value naming a *known* topic is visible only when it names
/// this student's own scope or the national scope, and then only if they
/// haven't opted out of that logical topic ([topicIntent]; absent from the
/// map defaults to visible, matching `reconcile()`'s own default-on for a
/// topic never toggled). A value naming the *same* topic but a *different*
/// campus's scope is hidden outright — that is the bug this guards against.
/// A value that matches no known topic at all — [kGeneralTopicId], or a
/// pre-migration bare topic id — defaults to visible.
///
/// Extracted as a top-level, `@visibleForTesting` function (rather than kept
/// as a private instance method) following the pattern
/// `decodeTopicSubscriptions` uses in `notification_service.dart`.
@visibleForTesting
bool isTopicAudienceVisible(
  String audienceValue,
  Map<String, bool> topicIntent, {
  required String? campusId,
}) {
  if (audienceValue == kGeneralTopicId) return true;
  final ownSlug = campusSlugFor(campusId);
  for (final topic in NotificationTopic.values) {
    if (audienceValue == '${topic.id}_$ownSlug' ||
        audienceValue == '${topic.id}_$kNationalSlug') {
      return topicIntent[topic.id] != false;
    }
    if (audienceValue.startsWith('${topic.id}_')) {
      // A known topic, but scoped to some other campus than this student's.
      return false;
    }
  }
  return true;
}

/// Whether a `broadcast` announcement should appear for a student on
/// [campusId].
///
/// New rows carry their channel in [audienceValue]: `general` (everyone) or
/// `general_{slug}`. Older rows have no `audience_value`; their channel is
/// derived from [rowCampusId] (`1`-`4` name a campus, anything else is
/// national and so everyone's).
@visibleForTesting
bool isBroadcastVisible({
  required String? audienceValue,
  required String? rowCampusId,
  required String? campusId,
}) {
  if (audienceValue != null && audienceValue.isNotEmpty) {
    if (audienceValue == kGeneralTopicId) return true;
    if (audienceValue.startsWith('${kGeneralTopicId}_')) {
      return audienceValue == '${kGeneralTopicId}_${campusSlugFor(campusId)}';
    }
    return true;
  }
  final rowSlug = campusSlugFor(rowCampusId);
  if (rowSlug == kNationalSlug) return true;
  return rowSlug == campusSlugFor(campusId);
}

/// Reads/writes the in-app notification inbox backed by the Appwrite
/// `announcements` and `user_notifications` collections in database `app`.
///
/// `announcements` decides what is in the inbox; `user_notifications` only
/// holds each student's read and cleared state. Clients cannot write that
/// table, so state is saved through `apps/api` ([NotificationsApi]).
///
/// Uses the shared [db] (`TablesDB`) and [realtime] singletons from
/// [appwrite_service.dart], mirroring [ChatService].
class NotificationInboxService {
  static const String _announcementsTable = 'announcements';
  static const String _userNotificationsTable = 'user_notifications';
  static const int _fetchLimit = 50;

  /// The National campus, whose announcements concern every student.
  static const String _nationalCampusId = '5';

  // Appwrite Query.equal('$id', [...]) supports a bounded list; chunk to stay
  // within reasonable request sizes.
  static const int _idChunkSize = 25;

  /// The `announcements` columns the inbox reads. Every announcements read
  /// selects them, so the table's `data` column is never fetched.
  ///
  /// The admin stores a sent announcement's push payload in `data`, as a JSON
  /// string. The SDK's `Row.fromMap` takes `map['data'] ?? map` as a row's
  /// data, so a fetched `data` column replaces the whole row and parsing
  /// throws `type 'String' is not a subtype of type 'Map<String, dynamic>'`.
  static final String _selectAnnouncementColumns = Query.select([
    '\$id',
    '\$createdAt',
    'title_en',
    'title_no',
    'body_en',
    'body_no',
    'category',
    'event_id',
    'deep_link',
    'sent_at',
    'audience_type',
    'audience_value',
    'campus_id',
    'source',
    'content_type',
    'content_id',
    'content_ids',
    'items',
    'image',
  ]);

  /// [tablesDb] stands in for the shared [db] in tests, and [api] for the
  /// `apps/api` client.
  NotificationInboxService({TablesDB? tablesDb, NotificationsApi? api})
    : _tablesDbOverride = tablesDb,
      _api = api ?? NotificationsApiClient();

  final TablesDB? _tablesDbOverride;
  TablesDB get _db => _tablesDbOverride ?? db;

  final NotificationsApi _api;

  Realtime get _realtime => realtime;

  String get _announcementsChannel => Channel.tablesdb(
    AppConstants.databaseId,
  ).table(_announcementsTable).row().toString();

  String get _userNotificationsChannel => Channel.tablesdb(
    AppConstants.databaseId,
  ).table(_userNotificationsTable).row().toString();

  /// Fetch the merged inbox for [userId] localized to [locale].
  ///
  /// [campusId] is the student's profile (home) campus. [topicIntent] is
  /// their logical topic intent — `news`/`events`/`jobs`/`shop` — as returned
  /// by `NotificationService.loadTopicIntent()`. Broadcast announcements
  /// always appear; a `topic` announcement (whose `audience_value` is a
  /// campus-scoped Appwrite topic id, e.g. `events_oslo`) is shown only when
  /// it is scoped to this student's campus (or national) and they haven't
  /// explicitly opted out of that topic's logical intent (default-show when
  /// the topic is absent from the map — see [isTopicAudienceVisible]).
  /// Broadcasts are filtered by [isBroadcastVisible], and anything sent before
  /// [joinedAt] (when the student's profile was created) is dropped.
  ///
  /// Announcements sent to people (`users` and `segment`) are listed from
  /// `announcements` too: their rows are readable only by their recipients.
  /// Then the student's `user_notifications` rows are read for exactly the
  /// announcements found, which gives each its read state, and drops the
  /// ones the student has cleared.
  Future<List<AppNotification>> fetchInbox({
    required String userId,
    required String locale,
    required String? campusId,
    Map<String, bool> topicIntent = const {},
    DateTime? joinedAt,
  }) async {
    try {
      // 1. Broadcast feed: sent announcements addressed to everyone. Query
      // broadcasts, topics and targeted sends separately, each with its own
      // limit, so a busy backlog of one can't push the others out of the
      // limited result set.
      final broadcastRows = await _db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: _announcementsTable,
        queries: [
          _selectAnnouncementColumns,
          Query.equal('status', 'sent'),
          Query.equal('audience_type', 'broadcast'),
          Query.orderDesc('sent_at'),
          Query.limit(_fetchLimit),
        ],
      );
      final topicRows = await _fetchTopicRows(campusId);
      final targetedRows = await _fetchTargetedRows();

      final announcementById = <String, Map<String, dynamic>>{};
      for (final row in broadcastRows.rows) {
        if (!isBroadcastVisible(
          audienceValue: row.data['audience_value'] as String?,
          rowCampusId: row.data['campus_id'] as String?,
          campusId: campusId,
        )) {
          continue;
        }
        announcementById[row.$id] = _rowToMap(row);
      }
      for (final row in topicRows) {
        // Hide topic announcements scoped to another campus, or opted out of.
        if (!_isTopicVisible(row.data, topicIntent, campusId: campusId)) {
          continue;
        }
        announcementById[row.$id] = _rowToMap(row);
      }
      // Row security has already narrowed targeted sends to this student.
      for (final row in targetedRows.rows) {
        announcementById[row.$id] = _rowToMap(row);
      }

      // 2. The student's state for exactly those announcements.
      final stateByAnnouncement = await _fetchStates(
        userId,
        announcementById.keys.toList(),
      );

      // 3. Drop what the student cleared and build the localized list.
      final items =
          announcementById.entries
              .where(
                (entry) =>
                    stateByAnnouncement[entry.key]?.data['cleared'] != true,
              )
              .map((entry) {
                final state = stateByAnnouncement[entry.key];
                return AppNotification.fromAnnouncement(
                  entry.value,
                  locale: locale,
                  read: state?.data['read'] == true,
                  userNotificationId: state?.$id,
                );
              })
              .where((n) => joinedAt == null || !n.createdAt.isBefore(joinedAt))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return items;
    } on AppwriteException catch (e) {
      throw NotificationInboxException('Failed to load inbox: ${e.message}');
    } catch (e) {
      throw NotificationInboxException('Failed to load inbox: $e');
    }
  }

  /// The newest [_fetchLimit] sent `topic` announcements that can concern a
  /// student on [campusId], newest first.
  ///
  /// Filtered by campus on the server, on the indexed `campus_id`, before the
  /// limit applies. Filtering only afterwards, on the client, let other
  /// campuses' announcements fill the limit: once they had published
  /// [_fetchLimit] newer ones, this student's own were never fetched at all.
  /// `audience_value` has no index and is not filtered on here; the caller
  /// still applies [_isTopicVisible], which checks it and the opt-outs.
  ///
  /// Two reads, merged: one for the student's campus and National, and one
  /// for rows with no campus, which is how an "All campuses" send is stored.
  /// Null cannot be matched inside an `equal` list, so it gets a read, and a
  /// limit, of its own.
  ///
  /// So a historical row whose `audience_value` is a bare logical topic, such
  /// as `events`, now reaches only students on its own campus or National, or
  /// everyone when its `campus_id` is null. It used to be fetched, and shown,
  /// for every campus.
  Future<List<models.Row>> _fetchTopicRows(String? campusId) async {
    final campusIds = <String>{
      if (campusId != null && campusId.isNotEmpty) campusId,
      _nationalCampusId,
    }.toList();

    List<String> topicQueries(String campusFilter) => [
      _selectAnnouncementColumns,
      Query.equal('status', 'sent'),
      Query.equal('audience_type', 'topic'),
      campusFilter,
      Query.orderDesc('sent_at'),
      Query.limit(_fetchLimit),
    ];

    final reads = await Future.wait([
      _db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: _announcementsTable,
        queries: topicQueries(Query.equal('campus_id', campusIds)),
      ),
      _db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: _announcementsTable,
        queries: topicQueries(Query.isNull('campus_id')),
      ),
    ]);

    final rowsById = <String, models.Row>{
      for (final read in reads)
        for (final row in read.rows) row.$id: row,
    };
    final newestFirst = rowsById.values.toList()
      ..sort((a, b) => _sentAt(b).compareTo(_sentAt(a)));
    return newestFirst.take(_fetchLimit).toList();
  }

  /// The newest [_fetchLimit] sent announcements addressed to people rather
  /// than to a topic: `users` and `segment` sends.
  ///
  /// The admin creates announcements without read permissions, and the send
  /// gives a targeted one `read` for its recipients only, so row security
  /// returns just the ones meant for this student. They used to be found
  /// through the student's newest `user_notifications` rows instead, which
  /// lost them once enough other announcements had been opened since.
  Future<models.RowList> _fetchTargetedRows() => _db.listRows(
    databaseId: AppConstants.databaseId,
    tableId: _announcementsTable,
    queries: [
      _selectAnnouncementColumns,
      Query.equal('status', 'sent'),
      Query.equal('audience_type', ['users', 'segment']),
      Query.orderDesc('sent_at'),
      Query.limit(_fetchLimit),
    ],
  );

  /// [userId]'s `user_notifications` rows for [announcementIds], by
  /// announcement id. Read by id, in chunks, rather than as the student's
  /// newest rows: a row is written whenever an announcement is opened, so the
  /// newest ones need not be the ones on screen.
  Future<Map<String, models.Row>> _fetchStates(
    String userId,
    List<String> announcementIds,
  ) async {
    final reads = await Future.wait([
      for (final chunk in _chunk(announcementIds, _idChunkSize))
        _db.listRows(
          databaseId: AppConstants.databaseId,
          tableId: _userNotificationsTable,
          queries: [
            Query.equal('user_id', userId),
            Query.equal('announcement_id', chunk),
            Query.limit(chunk.length),
          ],
        ),
    ]);
    return {
      for (final read in reads)
        for (final row in read.rows)
          if (row.data['announcement_id'] case final String id
              when id.isNotEmpty)
            id: row,
    };
  }

  /// When [row] was sent, for ordering. A row without a readable `sent_at`
  /// sorts last.
  static DateTime _sentAt(models.Row row) {
    final value = row.data['sent_at'];
    return (value is String ? DateTime.tryParse(value) : null) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
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
      final announcementRows = await _db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: _announcementsTable,
        queries: [
          _selectAnnouncementColumns,
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
        final userRows = await _db.listRows(
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

  /// Saves [announcementId] as read for the signed-in student.
  ///
  /// The app cannot create `user_notifications` rows itself (the table grants
  /// clients no create permission), so this goes through `apps/api`, which
  /// takes the student from the session.
  Future<void> markAsRead(String announcementId) async {
    try {
      await _api.markRead([announcementId]);
    } catch (e) {
      throw NotificationInboxException('Failed to mark as read: $e');
    }
  }

  /// Clears [announcementIds] from the signed-in student's inbox on every
  /// device, which also counts them read. Sent [kNotificationsApiBatchSize]
  /// at a time, one batch after another.
  ///
  /// Returns the ids that were not cleared, those of every batch that failed;
  /// empty when all were. A failure is reported this way, never thrown, so
  /// the caller can put back exactly the rows that did not clear.
  Future<Set<String>> clear(List<String> announcementIds) async {
    final failed = <String>{};
    final unique = announcementIds.toSet().toList();
    for (final batch in _chunk(unique, kNotificationsApiBatchSize)) {
      try {
        await _api.clear(batch);
      } catch (e) {
        debugPrint('NotificationInboxService.clear: a batch failed: $e');
        failed.addAll(batch);
      }
    }
    return failed;
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

  /// A `topic` announcement is visible only when it is scoped to [campusId]
  /// (or national) and the user hasn't opted out of its topic; broadcasts
  /// (and any non-topic audience) are always visible.
  bool _isTopicVisible(
    Map<String, dynamic> data,
    Map<String, bool> topicIntent, {
    required String? campusId,
  }) {
    if (data['audience_type'] != 'topic') return true;
    final audienceValue = data['audience_value'] as String?;
    if (audienceValue == null || audienceValue.isEmpty) return true;
    return isTopicAudienceVisible(
      audienceValue,
      topicIntent,
      campusId: campusId,
    );
  }

  Iterable<List<T>> _chunk<T>(List<T> source, int size) sync* {
    for (var i = 0; i < source.length; i += size) {
      yield source.sublist(
        i,
        i + size > source.length ? source.length : i + size,
      );
    }
  }
}

class NotificationInboxException implements Exception {
  final String message;
  NotificationInboxException(this.message);

  @override
  String toString() => message;
}
