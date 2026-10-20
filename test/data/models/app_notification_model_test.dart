import 'dart:convert';

import 'package:biso/data/models/app_notification_model.dart';
import 'package:biso/data/models/inbox_item.dart';
import 'package:biso/data/services/deep_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _doc({Object? items, Map<String, dynamic>? extra}) => {
  '\$id': 'a1',
  'title_en': 'Hello',
  'sent_at': '2026-09-01T10:00:00.000Z',
  'items': items,
  ...?extra,
};

String _itemsJson(int n) => jsonEncode([
  for (var i = 0; i < n; i++) {'type': 'event', 'id': 'e$i', 'title_en': 'E$i'},
]);

void main() {
  group('AppNotification.fromAnnouncement', () {
    test('a 3-element items JSON gives a burst', () {
      final n = AppNotification.fromAnnouncement(_doc(items: _itemsJson(3)));
      expect(n.items, hasLength(3));
      expect(n.isBurst, isTrue);
    });

    test('a single item is not a burst', () {
      final n = AppNotification.fromAnnouncement(_doc(items: _itemsJson(1)));
      expect(n.isBurst, isFalse);
    });

    test('invalid JSON gives no items', () {
      final n = AppNotification.fromAnnouncement(_doc(items: '{not json'));
      expect(n.items, isEmpty);
      expect(n.isBurst, isFalse);
    });

    test('content_type news gives the news filter', () {
      final n = AppNotification.fromAnnouncement(
        _doc(extra: {'content_type': 'news', 'content_id': 'n1'}),
      );
      expect(n.filter, InboxFilter.news);
      expect(n.contentId, 'n1');
    });

    test('filter mapping', () {
      InboxFilter f(Map<String, dynamic> extra) =>
          AppNotification.fromAnnouncement(_doc(extra: extra)).filter;
      expect(f({'content_type': 'event'}), InboxFilter.events);
      expect(f({'category': 'event'}), InboxFilter.events);
      expect(f({'content_type': 'job'}), InboxFilter.jobs);
      expect(f({'category': 'general'}), InboxFilter.fromBiso);
    });

    test('defaults and urgency', () {
      final n = AppNotification.fromAnnouncement(
        _doc(extra: {'category': 'urgent'}),
      );
      expect(n.source, 'manual');
      expect(n.isUrgent, isTrue);
      expect(n.image, isNull);
    });

    test('parses source, audience, campus and image URL', () {
      final n = AppNotification.fromAnnouncement(
        _doc(
          extra: {
            'source': 'auto',
            'audience_type': 'broadcast',
            'audience_value': 'general_oslo',
            'campus_id': '1',
            'image': 'https://x.test/a.png',
          },
        ),
      );
      expect(n.source, 'auto');
      expect(n.audienceValue, 'general_oslo');
      expect(n.campusId, '1');
      expect(n.image, 'https://x.test/a.png');
    });
  });

  group('InboxItem', () {
    test('route for each type', () {
      expect(
        const InboxItem(type: 'event', id: 'e1').route,
        eventRouteFor('e1'),
      );
      expect(const InboxItem(type: 'news', id: 'n1').route, newsRouteFor('n1'));
      expect(const InboxItem(type: 'job', id: 'j1').route, jobRouteFor('j1'));
    });

    test('title prefers the requested language and falls back', () {
      const both = InboxItem(
        type: 'news',
        id: 'n',
        titleEn: 'En',
        titleNo: 'No',
      );
      expect(both.title('no'), 'No');
      expect(both.title('en'), 'En');
      const onlyEn = InboxItem(type: 'news', id: 'n', titleEn: 'En');
      expect(onlyEn.title('no'), 'En');
      const onlyNo = InboxItem(type: 'news', id: 'n', titleNo: 'No');
      expect(onlyNo.title('en'), 'No');
    });

    test('listFromJson tolerates null, empty and invalid input', () {
      expect(InboxItem.listFromJson(null), isEmpty);
      expect(InboxItem.listFromJson(''), isEmpty);
      expect(InboxItem.listFromJson('nope'), isEmpty);
      expect(InboxItem.listFromJson('{"a":1}'), isEmpty);
    });

    test('listFromJson skips unknown types and missing ids', () {
      final items = InboxItem.listFromJson(
        jsonEncode([
          {'type': 'event', 'id': 'e1', 'date': '2026-09-01T10:00:00Z'},
          {'type': 'shop', 'id': 's1'},
          {'type': 'news'},
          {'type': 'job', 'id': ''},
          'junk',
          {'type': 'job', 'id': 'j1', 'campus_id': '2'},
        ]),
      );
      expect([for (final i in items) i.id], ['e1', 'j1']);
      expect(items.first.date, DateTime.utc(2026, 9, 1, 10));
      expect(items.last.campusId, '2');
    });
  });
}
