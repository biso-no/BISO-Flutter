import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:biso/core/constants/notification_topics.dart';
import 'package:biso/data/models/app_notification_model.dart';
import 'package:biso/data/services/notification_inbox_service.dart';
import 'package:biso/data/services/notifications_api_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `announcements` table, answering the reads `fetchInbox` makes the way
/// Appwrite would: `equal` (any of the listed values), `isNull`, `orderDesc`,
/// `limit` and `select`. Any other query method throws, so a query this fake
/// does not understand cannot pass silently. `user_notifications` answers the
/// same queries, from [userNotifications].
///
/// Rows go through the SDK's own `RowList.fromMap`, exactly as the real
/// `listRows` parses a response, so a column the SDK cannot parse fails here
/// the way it fails on a device.
class _FakeTablesDB extends TablesDB {
  _FakeTablesDB(this.announcements, {this.userNotifications = const []})
    : super(Client());

  final List<Map<String, dynamic>> announcements;
  final List<Map<String, dynamic>> userNotifications;

  /// The decoded queries of every `announcements` read, in call order.
  final List<List<Map<String, dynamic>>> announcementReads = [];

  /// The decoded queries of every `user_notifications` read, in call order.
  final List<List<Map<String, dynamic>>> userNotificationReads = [];

  @override
  Future<models.RowList> listRows({
    required String databaseId,
    required String tableId,
    List<String>? queries,
    String? transactionId,
    bool? total,
    int? ttl,
  }) async {
    final decoded = [
      for (final query in queries ?? const <String>[])
        jsonDecode(query) as Map<String, dynamic>,
    ];
    final List<Map<String, dynamic>> table;
    switch (tableId) {
      case 'announcements':
        table = announcements;
        announcementReads.add(decoded);
      case 'user_notifications':
        table = userNotifications;
        userNotificationReads.add(decoded);
      default:
        throw StateError('unexpected table $tableId');
    }

    Iterable<Map<String, dynamic>> rows = table;
    String? newestFirstBy;
    int? limit;
    List<String>? selected;
    for (final query in decoded) {
      final attribute = query['attribute'] as String?;
      final values = query['values'] as List<dynamic>? ?? const [];
      switch (query['method']) {
        case 'equal':
          rows = rows.where((row) => values.contains(row[attribute]));
        case 'isNull':
          rows = rows.where((row) => row[attribute] == null);
        case 'orderDesc':
          newestFirstBy = attribute;
        case 'limit':
          limit = values.single as int;
        case 'select':
          selected = values.cast<String>();
        default:
          throw UnsupportedError('unsupported query: $query');
      }
    }

    var result = rows.toList();
    final orderBy = newestFirstBy;
    if (orderBy != null) {
      result.sort(
        (a, b) => (b[orderBy] as String).compareTo(a[orderBy] as String),
      );
    }
    final max = limit;
    if (max != null && result.length > max) result = result.sublist(0, max);
    final columns = selected;
    return models.RowList.fromMap({
      'total': result.length,
      'rows': [
        for (final row in result)
          columns == null
              ? row
              : {
                  for (final column in columns)
                    if (row.containsKey(column)) column: row[column],
                },
      ],
    });
  }
}

Map<String, dynamic> _topicRow(
  String id, {
  required String? campusId,
  required String audienceValue,
  required DateTime sentAt,
}) => <String, dynamic>{
  '\$id': id,
  'status': 'sent',
  'audience_type': 'topic',
  'audience_value': audienceValue,
  'campus_id': campusId,
  'title_en': id,
  'sent_at': sentAt.toIso8601String(),
};

Map<String, dynamic> _broadcastRow(
  String id, {
  required DateTime sentAt,
  String? audienceValue,
  String? campusId,
}) => <String, dynamic>{
  '\$id': id,
  'status': 'sent',
  'audience_type': 'broadcast',
  'audience_value': audienceValue,
  'campus_id': campusId,
  'title_en': id,
  'sent_at': sentAt.toIso8601String(),
  'items': '[{"type":"news","id":"n1"}]',
  'image': 'file1',
  'content_type': 'news',
  'data': '{"x":1}',
};

void main() {
  group('isBroadcastVisible', () {
    bool visible(String? value, String? rowCampus, String? campus) =>
        isBroadcastVisible(
          audienceValue: value,
          rowCampusId: rowCampus,
          campusId: campus,
        );

    test('general is visible to everyone', () {
      expect(visible('general', null, '2'), isTrue);
    });
    test('general_bergen is visible to campus 2', () {
      expect(visible('general_bergen', '2', '2'), isTrue);
    });
    test('general_oslo is hidden from campus 2', () {
      expect(visible('general_oslo', '1', '2'), isFalse);
    });
    test('legacy null value with campus_id 1 is hidden from campus 2', () {
      expect(visible(null, '1', '2'), isFalse);
    });
    test('legacy null value with null campus_id is visible', () {
      expect(visible(null, null, '2'), isTrue);
    });
    test('legacy null value with campus_id 5 is visible', () {
      expect(visible(null, '5', '2'), isTrue);
    });
  });

  group('isTopicAudienceVisible', () {
    test(
      'hides a campus-scoped announcement when the student has turned that '
      'logical topic off - this is the case that regressed: audience_value '
      'is now "events_oslo", not the bare "events" the old lookup expected',
      () {
        expect(
          isTopicAudienceVisible('events_oslo', {
            'events': false,
          }, campusId: '1'),
          isFalse,
        );
      },
    );

    test('shows a campus-scoped announcement for the student\'s own campus '
        'when the topic is on', () {
      expect(
        isTopicAudienceVisible('events_oslo', {'events': true}, campusId: '1'),
        isTrue,
      );
    });

    test('hides an announcement scoped to a campus other than the student\'s '
        'own, even though the topic itself is on - this is the bug: push '
        'delivery is campus-scoped, so an Oslo student was never pushed a '
        'Bergen announcement, but the old campus-blind lookup showed it to '
        'them anyway', () {
      expect(
        isTopicAudienceVisible('events_bergen', {
          'events': true,
        }, campusId: '1'),
        isFalse,
      );
    });

    test('a national-scoped announcement is governed by the same logical topic '
        'as its campus-scoped sibling', () {
      expect(
        isTopicAudienceVisible('news_national', {'news': false}, campusId: '1'),
        isFalse,
      );
      expect(
        isTopicAudienceVisible('news_$kNationalSlug', {
          'news': true,
        }, campusId: '1'),
        isTrue,
      );
    });

    test('a topic switched off is hidden both for the student\'s own campus '
        'scope and the national scope', () {
      expect(
        isTopicAudienceVisible('events_oslo', {'events': false}, campusId: '1'),
        isFalse,
      );
      expect(
        isTopicAudienceVisible('events_national', {
          'events': false,
        }, campusId: '1'),
        isFalse,
      );
    });

    test(
      'the general topic is always visible regardless of intent or campus',
      () {
        expect(
          isTopicAudienceVisible(kGeneralTopicId, {}, campusId: '1'),
          isTrue,
        );
        expect(
          isTopicAudienceVisible(kGeneralTopicId, {
            'news': false,
            'events': false,
            'jobs': false,
            'shop': false,
          }, campusId: null),
          isTrue,
        );
      },
    );

    test('defaults to visible for a topic absent from the intent map, matching '
        "reconcile()'s own default-on behaviour for a topic the student has "
        'never toggled', () {
      expect(isTopicAudienceVisible('jobs_bergen', {}, campusId: '2'), isTrue);
    });

    test('defaults to visible for an unrecognised audience value rather than '
        'hiding it outright', () {
      expect(
        isTopicAudienceVisible('mystery_topic_oslo', {
          'events': false,
        }, campusId: '1'),
        isTrue,
      );
    });

    test('a bare legacy audience value - written before campus scoping existed '
        '- stays visible even when the student has switched that topic off, '
        'covering historical announcements that predate this branch', () {
      expect(
        isTopicAudienceVisible('events', {'events': false}, campusId: '1'),
        isTrue,
      );
    });

    test('covers every logical topic, not just events', () {
      for (final topic in NotificationTopic.values) {
        expect(
          isTopicAudienceVisible('${topic.id}_stavanger', {
            topic.id: false,
          }, campusId: '4'),
          isFalse,
          reason: '${topic.id} should be hidden when switched off',
        );
      }
    });

    test('a National-campus student (id "5") sees only national scope, not an '
        'arbitrary other campus - their own-campus scope and the national '
        'scope collapse to the same slug', () {
      expect(
        isTopicAudienceVisible('events_oslo', {'events': true}, campusId: '5'),
        isFalse,
        reason: 'not their campus',
      );
      expect(
        isTopicAudienceVisible('events_national', {
          'events': true,
        }, campusId: '5'),
        isTrue,
      );
    });

    test('a student with no profile campus (null) is treated the same as '
        'National, since campusSlugFor falls back to the national slug either '
        'way', () {
      expect(
        isTopicAudienceVisible('events_oslo', {'events': true}, campusId: null),
        isFalse,
        reason: 'not their campus',
      );
      expect(
        isTopicAudienceVisible('events_national', {
          'events': true,
        }, campusId: null),
        isTrue,
      );
    });
  });

  group('NotificationInboxService.fetchInbox', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUpAll(() {
      // Constructing an Appwrite Client asks path_provider for a cookie
      // directory, which has no implementation under `flutter test`.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => Directory.systemTemp.path,
          );
    });

    tearDownAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
    });

    final base = DateTime.utc(2026, 9, 1);
    DateTime at(int hours) => base.add(Duration(hours: hours));

    Future<List<String>> inboxIds(
      _FakeTablesDB db, {
      required String? campusId,
    }) async {
      final items = await NotificationInboxService(
        tablesDb: db,
      ).fetchInbox(userId: 'user-1', locale: 'en', campusId: campusId);
      return [for (final item in items) item.id];
    }

    /// Every read of topic announcements `fetchInbox` made.
    List<List<Map<String, dynamic>>> topicReads(_FakeTablesDB db) => [
      for (final read in db.announcementReads)
        if (read.any(
          (q) =>
              q['attribute'] == 'audience_type' &&
              (q['values'] as List).contains('topic'),
        ))
          read,
    ];

    /// How each topic read filtered on `campus_id`: `['equal', ...values]`,
    /// or `['isNull']`.
    List<List<Object?>> campusFilters(_FakeTablesDB db) => [
      for (final read in topicReads(db))
        for (final q in read)
          if (q['attribute'] == 'campus_id')
            q['method'] == 'isNull'
                ? <Object?>['isNull']
                : <Object?>['equal', ...(q['values'] as List)],
    ];

    /// Announcements for three audiences, each older than every one of
    /// [newerElsewhere] topic announcements published for Bergen.
    List<Map<String, dynamic>> announcements({int newerElsewhere = 0}) => [
      for (var i = 0; i < newerElsewhere; i++)
        _topicRow(
          'bergen-$i',
          campusId: '2',
          audienceValue: 'events_bergen',
          sentAt: at(100 + i),
        ),
      _topicRow(
        'oslo',
        campusId: '1',
        audienceValue: 'events_oslo',
        sentAt: at(3),
      ),
      _topicRow(
        'national',
        campusId: '5',
        audienceValue: 'events_national',
        sentAt: at(2),
      ),
      _topicRow(
        'all-campuses',
        campusId: null,
        audienceValue: 'events_national',
        sentAt: at(1),
      ),
    ];

    test('still shows the student\'s own-campus, national and all-campuses '
        'topic announcements when more than the fetch limit of newer ones '
        'belong to other campuses: the limit was applied before the campus '
        'filter, so they were never fetched at all', () async {
      final db = _FakeTablesDB(announcements(newerElsewhere: 120));

      expect(await inboxIds(db, campusId: '1'), [
        'oslo',
        'national',
        'all-campuses',
      ]);
    });

    test(
      'asks for the student\'s campus and national by the indexed campus_id, '
      'and for all-campuses rows with isNull - null never goes inside the '
      'equal list - keeping the status, ordering and limit of each read',
      () async {
        final db = _FakeTablesDB(announcements());

        await inboxIds(db, campusId: '1');

        expect(
          campusFilters(db),
          unorderedEquals([
            ['equal', '1', '5'],
            ['isNull'],
          ]),
        );
        expect(
          campusFilters(db).expand((filter) => filter),
          isNot(contains(null)),
        );
        for (final read in topicReads(db)) {
          expect(
            read,
            anyElement(
              equals({
                'method': 'equal',
                'attribute': 'status',
                'values': ['sent'],
              }),
            ),
          );
          expect(
            read,
            anyElement(equals({'method': 'orderDesc', 'attribute': 'sent_at'})),
          );
          expect(read, anyElement(containsPair('method', 'limit')));
        }
      },
    );

    for (final campusId in <String?>['5', null]) {
      test(
        'a student whose campus is ${campusId == null ? 'unset' : '"5"'} asks '
        'for campus_id "5" alone, and sees national and all-campuses '
        'announcements but not another campus\'s',
        () async {
          final db = _FakeTablesDB(announcements(newerElsewhere: 120));

          expect(await inboxIds(db, campusId: campusId), [
            'national',
            'all-campuses',
          ]);
          expect(
            campusFilters(db),
            unorderedEquals([
              ['equal', '5'],
              ['isNull'],
            ]),
          );
        },
      );
    }

    test(
      'merges the two reads, each cut to the fetch limit on its own, into the '
      'newest rows of their union up to that limit: it must pick across both '
      'reads rather than favour either, or split the limit between them',
      () async {
        // More rows than the fetch limit of 50 for each read, unevenly spread
        // in time: the newest 50 of the two together are 35 all-campuses rows
        // and 15 own-campus ones. Newer than all of them are rows for another
        // campus, which neither read may return.
        final rows = [
          for (var i = 0; i < 60; i++)
            _topicRow(
              'oslo-$i',
              campusId: '1',
              audienceValue: 'events_oslo',
              sentAt: at(2 * i),
            ),
          for (var i = 0; i < 60; i++)
            _topicRow(
              'all-$i',
              campusId: null,
              audienceValue: 'events_national',
              sentAt: at(41 + 2 * i),
            ),
          for (var i = 0; i < 10; i++)
            _topicRow(
              'bergen-$i',
              campusId: '2',
              audienceValue: 'events_bergen',
              sentAt: at(200 + i),
            ),
        ];
        final newestOfUnion = [
          for (final row
              in [...rows]..sort(
                (a, b) =>
                    (b['sent_at'] as String).compareTo(a['sent_at'] as String),
              ))
            if (row['campus_id'] != '2') row['\$id'] as String,
        ].take(50).toList();

        final ids = await inboxIds(_FakeTablesDB(rows), campusId: '1');

        expect(ids, hasLength(50));
        expect(ids, newestOfUnion);
        expect(ids.where((id) => id.startsWith('all-')), hasLength(35));
      },
    );

    test('a historical row with a bare legacy audience_value such as "events" '
        'now reaches only students on its own campus, national, or everyone '
        'when its campus_id is null - it used to be fetched, and shown, for '
        'every campus', () async {
      final rows = [
        _topicRow(
          'legacy-bergen',
          campusId: '2',
          audienceValue: 'events',
          sentAt: at(2),
        ),
        _topicRow(
          'legacy-all-campuses',
          campusId: null,
          audienceValue: 'events',
          sentAt: at(1),
        ),
      ];

      expect(await inboxIds(_FakeTablesDB(rows), campusId: '1'), [
        'legacy-all-campuses',
      ]);
      expect(await inboxIds(_FakeTablesDB(rows), campusId: '2'), [
        'legacy-bergen',
        'legacy-all-campuses',
      ]);
    });
  });

  group('fetchInbox joinedAt and new columns', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUpAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => Directory.systemTemp.path,
          );
    });

    final joined = DateTime.utc(2026, 9, 1);

    test(
      'drops a broadcast sent before joinedAt and keeps one after',
      () async {
        final db = _FakeTablesDB([
          _broadcastRow(
            'before',
            sentAt: joined.subtract(const Duration(days: 1)),
          ),
          _broadcastRow('after', sentAt: joined.add(const Duration(days: 1))),
        ]);
        final items = await NotificationInboxService(tablesDb: db).fetchInbox(
          userId: 'u',
          locale: 'en',
          campusId: '2',
          joinedAt: joined,
        );
        expect([for (final i in items) i.id], ['after']);
        expect(items.single.isBurst, isFalse);
        expect(items.single.items.single.id, 'n1');
        expect(items.single.contentType, 'news');
        expect(items.single.image, contains('file1'));
      },
    );

    test('hides another campus broadcast', () async {
      final db = _FakeTablesDB([
        _broadcastRow('oslo', sentAt: joined, audienceValue: 'general_oslo'),
        _broadcastRow('all', sentAt: joined, audienceValue: 'general'),
      ]);
      final items = await NotificationInboxService(
        tablesDb: db,
      ).fetchInbox(userId: 'u', locale: 'en', campusId: '2');
      expect([for (final i in items) i.id], ['all']);
    });

    test('a user_notifications row does not let a hidden broadcast back in, '
        'but a users-audience row still shows', () async {
      final db = _FakeTablesDB(
        [
          _broadcastRow('oslo', sentAt: joined, audienceValue: 'general_oslo'),
          {
            '\$id': 'direct',
            'status': 'sent',
            'audience_type': 'users',
            'title_en': 'direct',
            'sent_at': joined.toIso8601String(),
          },
        ],
        userNotifications: [
          {
            '\$id': 'un1',
            '\$createdAt': '2026-09-01T00:00:00.000Z',
            'user_id': 'u',
            'announcement_id': 'oslo',
            'read': true,
          },
          {
            '\$id': 'un2',
            '\$createdAt': '2026-09-01T00:00:00.000Z',
            'user_id': 'u',
            'announcement_id': 'direct',
            'read': false,
          },
        ],
      );
      final items = await NotificationInboxService(
        tablesDb: db,
      ).fetchInbox(userId: 'u', locale: 'en', campusId: '2');
      expect([for (final i in items) i.id], ['direct']);
    });

    test('selects items, image and content_type but never data', () async {
      final db = _FakeTablesDB([_broadcastRow('a', sentAt: joined)]);
      await NotificationInboxService(
        tablesDb: db,
      ).fetchInbox(userId: 'u', locale: 'en', campusId: '2');
      final selects = [
        for (final read in db.announcementReads)
          for (final q in read)
            if (q['method'] == 'select') (q['values'] as List).cast<String>(),
      ];
      expect(selects, isNotEmpty);
      for (final columns in selects) {
        expect(columns, containsAll(['items', 'image', 'content_type']));
        expect(columns, isNot(contains('data')));
      }
    });
  });

  group('announcement rows with a data column', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUpAll(() {
      // Constructing an Appwrite Client asks path_provider for a cookie
      // directory, which has no implementation under `flutter test`.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => Directory.systemTemp.path,
          );
    });

    tearDownAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
    });

    /// A broadcast as the admin leaves it once sent: the push payload is kept,
    /// as a JSON string, in the row's own `data` column. The SDK's
    /// `Row.fromMap` reads `map['data'] ?? map` as the row's data, so when that
    /// column is fetched the string replaces the whole row and parsing throws.
    Map<String, dynamic> sentBroadcast() => <String, dynamic>{
      '\$id': 'announcement-1',
      '\$createdAt': '2026-10-19T12:00:00.000+00:00',
      'status': 'sent',
      'audience_type': 'broadcast',
      'title_en': 'Hello',
      'body_en': '<p>World</p>',
      'category': 'general',
      'deep_link': 'biso://announcement?id=announcement-1',
      'sent_at': '2026-10-19T12:00:00.000+00:00',
      'data': jsonEncode({
        'type': 'announcement',
        'announcement_id': 'announcement-1',
        'event_id': '',
        'segment_id': '',
        'deep_link': 'biso://announcement?id=announcement-1',
        'category': 'general',
      }),
    };

    test('fetchAnnouncementById loads it - tapping its push opens this, and it '
        'failed with "type \'String\' is not a subtype of type '
        '\'Map<String, dynamic>\'"', () async {
      final notification = await NotificationInboxService(
        tablesDb: _FakeTablesDB([sentBroadcast()]),
      ).fetchAnnouncementById(announcementId: 'announcement-1', locale: 'en');

      expect(notification, isNotNull);
      expect(notification!.id, 'announcement-1');
      expect(notification.title, 'Hello');
      expect(notification.body, 'World');
      expect(notification.deepLink, 'biso://announcement?id=announcement-1');
    });

    test('fetchInbox lists it', () async {
      final items = await NotificationInboxService(
        tablesDb: _FakeTablesDB([sentBroadcast()]),
      ).fetchInbox(userId: 'user-1', locale: 'en', campusId: '1');

      expect([for (final item in items) item.id], ['announcement-1']);
      expect(items.single.title, 'Hello');
    });
  });

  group('fetchInbox read state', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUpAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => Directory.systemTemp.path,
          );
    });

    tearDownAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
    });

    final base = DateTime.utc(2026, 9, 1);
    String at(int hours) => base.add(Duration(hours: hours)).toIso8601String();

    Map<String, dynamic> targeted(
      String id, {
      String audienceType = 'users',
      int hours = 0,
    }) => <String, dynamic>{
      '\$id': id,
      'status': 'sent',
      'audience_type': audienceType,
      'title_en': id,
      'sent_at': at(hours),
    };

    /// The student's `user_notifications` row for [announcementId].
    Map<String, dynamic> stateRow(
      String announcementId, {
      bool read = false,
      bool cleared = false,
      int hours = 0,
    }) => <String, dynamic>{
      '\$id': 'row-$announcementId',
      '\$createdAt': at(hours),
      'user_id': 'u',
      'announcement_id': announcementId,
      'read': read,
      'cleared': cleared,
    };

    /// Rows for 60 announcements other than the ones under test, all newer.
    List<Map<String, dynamic>> newerRows() => [
      for (var i = 0; i < 60; i++)
        stateRow('other-$i', read: true, hours: 100 + i),
    ];

    Future<List<AppNotification>> inbox(_FakeTablesDB db) =>
        NotificationInboxService(
          tablesDb: db,
        ).fetchInbox(userId: 'u', locale: 'en', campusId: '2');

    bool has(
      List<Map<String, dynamic>> read,
      String method, [
      String? attribute,
      List<Object?>? values,
    ]) => read.any(
      (q) =>
          q['method'] == method &&
          (attribute == null || q['attribute'] == attribute) &&
          (values == null || _sameList(q['values'] as List?, values)),
    );

    test('lists targeted announcements from announcements: sent, '
        'audience_type users or segment, newest sent_at first, limit 50, '
        'selected columns', () async {
      final db = _FakeTablesDB([targeted('t1')]);

      await inbox(db);

      final reads = [
        for (final read in db.announcementReads)
          if (has(read, 'equal', 'audience_type', ['users', 'segment'])) read,
      ];
      expect(reads, hasLength(1));
      final read = reads.single;
      expect(has(read, 'equal', 'status', ['sent']), isTrue);
      expect(has(read, 'orderDesc', 'sent_at'), isTrue);
      expect(has(read, 'limit', null, [50]), isTrue);
      expect(has(read, 'select'), isTrue);
    });

    test(
      'shows a targeted announcement that has no user_notifications row',
      () async {
        final db = _FakeTablesDB([
          targeted('t1'),
          targeted('t2', audienceType: 'segment', hours: 1),
        ]);

        expect([for (final n in await inbox(db)) n.id], ['t2', 't1']);
      },
    );

    test(
      'shows a targeted announcement however many newer rows the student has',
      () async {
        final db = _FakeTablesDB(
          [targeted('t1')],
          userNotifications: [stateRow('t1'), ...newerRows()],
        );

        expect([for (final n in await inbox(db)) n.id], ['t1']);
      },
    );

    test(
      'reads state for exactly the announcements shown, at most 25 ids a read',
      () async {
        final db = _FakeTablesDB([
          for (var i = 0; i < 30; i++)
            _broadcastRow('b$i', sentAt: base.add(Duration(hours: i))),
        ]);

        final shown = {for (final n in await inbox(db)) n.id};

        expect(shown, hasLength(30));
        final asked = <String>{};
        for (final read in db.userNotificationReads) {
          expect(has(read, 'equal', 'user_id', ['u']), isTrue);
          final ids = [
            for (final q in read)
              if (q['attribute'] == 'announcement_id')
                ...(q['values'] as List).cast<String>(),
          ];
          expect(ids.length, lessThanOrEqualTo(25));
          asked.addAll(ids);
        }
        expect(asked, shown);
      },
    );

    test('marks an announcement read from its row', () async {
      final db = _FakeTablesDB(
        [_broadcastRow('b1', sentAt: base)],
        userNotifications: [stateRow('b1', read: true)],
      );

      final item = (await inbox(db)).single;

      expect(item.read, isTrue);
      expect(item.userNotificationId, 'row-b1');
    });

    test(
      'drops cleared announcements: broadcast, topic and targeted',
      () async {
        final db = _FakeTablesDB(
          [
            _broadcastRow('b1', sentAt: base),
            _broadcastRow('b2', sentAt: base),
            _topicRow(
              'tp',
              campusId: '2',
              audienceValue: 'events_bergen',
              sentAt: base,
            ),
            targeted('t1'),
          ],
          userNotifications: [
            stateRow('b1', cleared: true, read: true),
            stateRow('tp', cleared: true, read: true),
            stateRow('t1', cleared: true, read: true),
          ],
        );

        expect([for (final n in await inbox(db)) n.id], ['b2']);
      },
    );

    test(
      'finds the state of an announcement whose row is older than 50 newer ones',
      () async {
        final db = _FakeTablesDB(
          [_broadcastRow('b1', sentAt: base)],
          userNotifications: [
            stateRow('b1', cleared: true, read: true),
            ...newerRows(),
          ],
        );

        expect(await inbox(db), isEmpty);
      },
    );
  });

  group('markAsRead and clear', () {
    late _FakeNotificationsApi api;
    late NotificationInboxService service;

    setUp(() {
      api = _FakeNotificationsApi();
      service = NotificationInboxService(api: api);
    });

    test('markAsRead sends the one id', () async {
      await service.markAsRead('a');

      expect(api.readCalls, [
        ['a'],
      ]);
    });

    test('markAsRead throws NotificationInboxException when the API fails', () {
      api.failReads = true;

      expect(
        service.markAsRead('a'),
        throwsA(isA<NotificationInboxException>()),
      );
    });

    test(
      'clear sends the ids once each, in batches of 100, in order',
      () async {
        final ids = [for (var i = 0; i < 250; i++) 'a$i'];

        final failed = await service.clear([...ids, 'a0']);

        expect(failed, isEmpty);
        expect(
          [for (final call in api.clearCalls) call.length],
          [100, 100, 50],
        );
        expect(api.clearCalls.expand((call) => call), ids);
      },
    );

    test('clear returns only the ids of a batch that failed', () async {
      final ids = [for (var i = 0; i < 250; i++) 'a$i'];
      api.failingClearCalls = {2};

      final failed = await service.clear(ids);

      expect(failed, ids.sublist(100, 200).toSet());
    });

    test('clear with no ids sends nothing', () async {
      expect(await service.clear(const []), isEmpty);
      expect(api.clearCalls, isEmpty);
    });
  });
}

bool _sameList(List<Object?>? a, List<Object?> b) =>
    a != null &&
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);

/// Records each call's ids; fails the reads, or chosen clear calls, on demand.
class _FakeNotificationsApi implements NotificationsApi {
  final List<List<String>> readCalls = [];
  final List<List<String>> clearCalls = [];

  bool failReads = false;

  /// 1-indexed clear calls that fail.
  Set<int> failingClearCalls = {};

  @override
  Future<void> markRead(List<String> announcementIds) async {
    readCalls.add(List.of(announcementIds));
    if (failReads) {
      throw const NotificationsApiException(
        NotificationsApiErrorKind.unavailable,
        statusCode: 503,
      );
    }
  }

  @override
  Future<void> clear(List<String> announcementIds) async {
    clearCalls.add(List.of(announcementIds));
    if (failingClearCalls.contains(clearCalls.length)) {
      throw const NotificationsApiException(
        NotificationsApiErrorKind.unavailable,
        statusCode: 503,
      );
    }
  }
}
