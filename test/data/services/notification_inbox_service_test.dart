import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:biso/core/constants/notification_topics.dart';
import 'package:biso/data/services/notification_inbox_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `announcements` table, answering the reads `fetchInbox` makes the way
/// Appwrite would: `equal` (any of the listed values), `isNull`, `orderDesc`
/// and `limit`. Any other query method throws, so a query this fake does not
/// understand cannot pass silently. `user_notifications` is empty.
class _FakeTablesDB extends TablesDB {
  _FakeTablesDB(this.announcements) : super(Client());

  final List<Map<String, dynamic>> announcements;

  /// The decoded queries of every `announcements` read, in call order.
  final List<List<Map<String, dynamic>>> announcementReads = [];

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
        table = const [];
      default:
        throw StateError('unexpected table $tableId');
    }

    Iterable<Map<String, dynamic>> rows = table;
    String? newestFirstBy;
    int? limit;
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
    return models.RowList(
      total: result.length,
      rows: [
        for (final row in result)
          models.Row(
            $id: row['\$id'] as String,
            $sequence: '0',
            $tableId: tableId,
            $databaseId: databaseId,
            $createdAt: '',
            $updatedAt: '',
            $permissions: const [],
            data: row,
          ),
      ],
    );
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

void main() {
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

    test(
      'still shows the student\'s own-campus, national and all-campuses '
      'topic announcements when more than the fetch limit of newer ones '
      'belong to other campuses: the limit was applied before the campus '
      'filter, so they were never fetched at all',
      () async {
        final db = _FakeTablesDB(announcements(newerElsewhere: 120));

        expect(await inboxIds(db, campusId: '1'), [
          'oslo',
          'national',
          'all-campuses',
        ]);
      },
    );

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
        expect(campusFilters(db).expand((filter) => filter), isNot(contains(null)));
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
      'merges both reads newest first and keeps only the newest topic rows '
      'up to the fetch limit',
      () async {
        // Own-campus and all-campuses rows interleaved in time, with more of
        // them together than the fetch limit allows.
        final rows = [
          for (var i = 0; i < 40; i++) ...[
            _topicRow(
              'oslo-$i',
              campusId: '1',
              audienceValue: 'events_oslo',
              sentAt: at(2 * i),
            ),
            _topicRow(
              'all-$i',
              campusId: null,
              audienceValue: 'events_national',
              sentAt: at(2 * i + 1),
            ),
          ],
        ];
        final newestFirst = [
          for (final row
              in [...rows]..sort(
                (a, b) =>
                    (b['sent_at'] as String).compareTo(a['sent_at'] as String),
              ))
            row['\$id'] as String,
        ];

        final ids = await inboxIds(_FakeTablesDB(rows), campusId: '1');

        expect(ids.length, lessThan(rows.length), reason: 'limit applied');
        expect(ids, newestFirst.take(ids.length).toList());
      },
    );

    test(
      'a historical row with a bare legacy audience_value such as "events" '
      'now reaches only students on its own campus, national, or everyone '
      'when its campus_id is null - it used to be fetched, and shown, for '
      'every campus',
      () async {
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
      },
    );
  });
}
