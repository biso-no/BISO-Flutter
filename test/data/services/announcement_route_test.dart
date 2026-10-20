import 'package:biso/data/models/app_notification_model.dart';
import 'package:biso/data/services/announcement_route.dart';
import 'package:biso/data/services/deep_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

AppNotification _n({
  String id = 'a1',
  String? deepLink,
  String? contentType,
  String? contentId,
  String? eventId,
}) => AppNotification(
  id: id,
  title: 't',
  body: '',
  category: 'general',
  createdAt: DateTime(2026, 10, 20),
  deepLink: deepLink,
  contentType: contentType,
  contentId: contentId,
  eventId: eventId,
);

void main() {
  group('routeForDeepLink', () {
    test('maps the content links a notification carries', () {
      expect(
        routeForDeepLink(Uri.parse('biso://event?id=e1')),
        '/explore/events/e1',
      );
      expect(
        routeForDeepLink(Uri.parse('biso://news?id=n1')),
        '/explore/news/n1',
      );
      expect(
        routeForDeepLink(Uri.parse('biso://job?id=j1')),
        '/explore/volunteer/j1',
      );
      expect(
        routeForDeepLink(Uri.parse('biso://announcement?id=a9')),
        '/announcements/a9',
      );
      expect(
        routeForDeepLink(Uri.parse('https://biso.no/app/events/autumn-party')),
        '/explore/events/autumn-party',
      );
      expect(
        routeForDeepLink(Uri.parse('https://biso.no/app/news/n1')),
        '/explore/news/n1',
      );
    });

    test('maps the shop, product, membership and tab links as before', () {
      final cases = {
        'biso://shop/order?orderId=o1&status=paid':
            '/explore/products/order/o1?status=paid',
        'biso://shop/orders': '/explore/products/orders',
        'biso://shop/cart': '/explore/products/cart',
        'biso://shop': '/explore/products',
        'biso://product?id=p1': '/explore/products/p1',
        'biso://product': '/explore/products',
        'biso://membership?orderId=o3': '/profile/membership?orderId=o3',
        'biso://job': '/explore/volunteer',
        'https://biso.no/app/shop/order/o2': '/explore/products/order/o2',
        'https://biso.no/app/shop/cart': '/explore/products/cart',
        'https://biso.no/app/marketplace/p2': '/explore/products/p2',
        'https://biso.no/app/jobs/j3': '/explore/volunteer/j3',
        'https://www.biso.no/events': '/explore/events',
        'https://biso.no/app/profile': '/profile',
        'https://biso.no/': '/home',
      };
      for (final MapEntry(key: link, value: route) in cases.entries) {
        expect(routeForDeepLink(Uri.parse(link)), route, reason: link);
      }
    });

    test('is null for links that open no plain in-app location', () {
      expect(routeForDeepLink(Uri.parse('biso://nowhere?id=1')), isNull);
      expect(routeForDeepLink(Uri.parse('biso://event')), isNull);
      expect(routeForDeepLink(Uri.parse('biso://expense?id=x1')), isNull);
      expect(routeForDeepLink(Uri.parse('biso://chat?id=c1')), isNull);
      expect(
        routeForDeepLink(Uri.parse('https://biso.no/app/expenses/new')),
        isNull,
      );
      expect(routeForDeepLink(Uri.parse('biso://announcement')), isNull);
      expect(routeForDeepLink(Uri.parse('https://example.com/x')), isNull);
      expect(
        routeForDeepLink(
          Uri.parse('https://biso.no/auth/verify?userId=u&secret=s'),
        ),
        isNull,
        reason: 'a sign-in link is not something to open from the inbox',
      );
    });
  });

  group('announcementRouteFor', () {
    test('a news deep link opens the article', () {
      expect(
        announcementRouteFor(_n(deepLink: 'biso://news?id=n1')),
        '/explore/news/n1',
      );
    });

    test('the deep link wins over the linked content', () {
      expect(
        announcementRouteFor(
          _n(
            deepLink: 'biso://news?id=n1',
            contentType: 'event',
            contentId: 'e1',
          ),
        ),
        '/explore/news/n1',
      );
    });

    test('without a deep link, content_type and content_id', () {
      expect(
        announcementRouteFor(
          _n(deepLink: '', contentType: 'event', contentId: 'e1'),
        ),
        '/explore/events/e1',
      );
      expect(
        announcementRouteFor(_n(contentType: 'news', contentId: 'n2')),
        '/explore/news/n2',
      );
      expect(
        announcementRouteFor(_n(contentType: 'job', contentId: 'j2')),
        '/explore/volunteer/j2',
      );
    });

    test('a deep link that opens nothing falls through to the content', () {
      expect(
        announcementRouteFor(
          _n(deepLink: 'biso://nowhere', contentType: 'event', contentId: 'e1'),
        ),
        '/explore/events/e1',
      );
    });

    test('only a legacy event_id opens the event', () {
      expect(announcementRouteFor(_n(eventId: 'e7')), eventRouteFor('e7'));
    });

    test('nothing linked opens the announcement itself', () {
      expect(announcementRouteFor(_n(id: 'a1')), '/announcements/a1');
    });

    test('nothing at all opens nowhere', () {
      expect(announcementRouteFor(_n(id: '')), isNull);
    });
  });

  test('the push payload and the inbox row resolve the same route', () {
    final cases = <(AppNotification, Map<String, dynamic>)>[
      (
        _n(deepLink: 'biso://news?id=n1'),
        {'announcement_id': 'a1', 'deep_link': 'biso://news?id=n1'},
      ),
      (
        _n(deepLink: '', contentType: 'event', contentId: 'e1'),
        {
          'announcement_id': 'a1',
          'deep_link': '',
          'content_type': 'event',
          'content_id': 'e1',
        },
      ),
      (_n(eventId: 'e7'), {'announcement_id': 'a1', 'event_id': 'e7'}),
      (_n(), {'announcement_id': 'a1'}),
    ];
    for (final (notification, data) in cases) {
      expect(
        announcementRouteForData(data),
        announcementRouteFor(notification),
        reason: '$data',
      );
    }
  });
}
