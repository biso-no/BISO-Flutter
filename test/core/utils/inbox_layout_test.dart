import 'package:biso/core/utils/inbox_layout.dart';
import 'package:biso/data/models/app_notification_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 10, 15);

  AppNotification n(
    String id,
    DateTime at, {
    String category = 'general',
    bool read = false,
    String? contentType,
  }) => AppNotification(
    id: id,
    title: id,
    body: '',
    category: category,
    createdAt: at,
    read: read,
    contentType: contentType,
  );

  List<String> ids(List<AppNotification> l) => [for (final i in l) i.id];

  group('pinUrgent', () {
    test('an unread urgent row from 2 days ago is pinned first', () {
      final result = pinUrgent([
        n('a', now),
        n('u', now.subtract(const Duration(days: 2)), category: 'urgent'),
        n('b', now),
      ], now);
      expect(ids(result), ['u', 'a', 'b']);
    });

    test('a read urgent row is not pinned', () {
      final result = pinUrgent([
        n('a', now),
        n(
          'u',
          now.subtract(const Duration(days: 2)),
          category: 'urgent',
          read: true,
        ),
      ], now);
      expect(ids(result), ['a', 'u']);
    });

    test('a 4-day-old urgent row is not pinned', () {
      final result = pinUrgent([
        n('a', now),
        n('u', now.subtract(const Duration(days: 4)), category: 'urgent'),
      ], now);
      expect(ids(result), ['a', 'u']);
    });

    test('pinned rows are newest first', () {
      final result = pinUrgent([
        n('old', now.subtract(const Duration(days: 2)), category: 'urgent'),
        n('new', now.subtract(const Duration(hours: 1)), category: 'urgent'),
      ], now);
      expect(ids(result), ['new', 'old']);
    });
  });

  group('groupByDay', () {
    test('boundaries use calendar days relative to now', () {
      final sections = groupByDay([
        n('today-early', DateTime(2026, 9, 10)),
        n('yesterday-late', DateTime(2026, 9, 9, 23, 59)),
        n('yesterday-early', DateTime(2026, 9, 9)),
        n('two-days', DateTime(2026, 9, 8, 12)),
        n('seven-days', DateTime(2026, 9, 3, 12)),
        n('eight-days', DateTime(2026, 9, 2, 12)),
      ], now);
      expect(
        [for (final s in sections) s.day],
        [
          InboxDay.today,
          InboxDay.yesterday,
          InboxDay.thisWeek,
          InboxDay.earlier,
        ],
      );
      expect(ids(sections[0].items), ['today-early']);
      expect(ids(sections[1].items), ['yesterday-late', 'yesterday-early']);
      expect(ids(sections[2].items), ['two-days', 'seven-days']);
      expect(ids(sections[3].items), ['eight-days']);
    });

    test('pinned urgent rows are excluded and empty groups omitted', () {
      final sections = groupByDay([
        n('u', now, category: 'urgent'),
        n('x', now.subtract(const Duration(days: 20))),
      ], now);
      expect([for (final s in sections) s.day], [InboxDay.earlier]);
      expect(ids(sections.single.items), ['x']);
    });
  });

  group('applyFilter', () {
    final items = [
      n('e', now, contentType: 'event'),
      n('n', now, contentType: 'news'),
      n('j', now, contentType: 'job'),
      n('b', now),
    ];
    test('all keeps everything', () {
      expect(ids(applyFilter(items, InboxFilter.all)), ['e', 'n', 'j', 'b']);
    });
    test('each filter selects its rows', () {
      expect(ids(applyFilter(items, InboxFilter.events)), ['e']);
      expect(ids(applyFilter(items, InboxFilter.news)), ['n']);
      expect(ids(applyFilter(items, InboxFilter.jobs)), ['j']);
      expect(ids(applyFilter(items, InboxFilter.fromBiso)), ['b']);
    });
  });
}
