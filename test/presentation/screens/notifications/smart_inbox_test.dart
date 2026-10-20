import 'package:biso/data/models/app_notification_model.dart';
import 'package:biso/data/models/inbox_item.dart';
import 'package:biso/presentation/screens/notifications/announcement_detail_screen.dart';
import 'package:biso/presentation/screens/notifications/notifications_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/notification/notification_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/biso_screen_harness.dart';

final _now = DateTime(2026, 10, 20, 12);

AppNotification _n(
  String id,
  String title, {
  String category = 'general',
  String? contentType,
  Duration age = const Duration(hours: 1),
  bool read = false,
  List<InboxItem> items = const [],
}) => AppNotification(
  id: id,
  title: title,
  body: '',
  category: category,
  contentType: contentType,
  createdAt: _now.subtract(age),
  read: read,
  items: items,
);

class _FakeInbox extends StateNotifier<NotificationInboxState>
    implements NotificationInboxNotifier {
  _FakeInbox(super.state);

  final marked = <String>[];

  @override
  Future<void> markRead(AppNotification notification) async {
    marked.add(notification.id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> _overrides(List<AppNotification> items) => [
  notificationInboxProvider.overrideWith(
    (ref) => _FakeInbox(NotificationInboxState(items: items)),
  ),
];

Future<void> _pump(
  WidgetTester tester,
  List<AppNotification> items, {
  Locale? locale,
  List<RouteBase> routes = const [],
}) => pumpBisoScreen(
  tester,
  NotificationsScreen(clock: () => _now),
  inShell: false,
  routed: routes.isNotEmpty,
  extraRoutes: routes,
  locale: locale,
  overrides: _overrides(items),
);

final _burstItems = [
  for (final i in [1, 2, 3])
    InboxItem(
      type: 'event',
      id: 'e$i',
      titleEn: 'Bergen event $i',
      date: DateTime(2026, 11, i),
    ),
];

void main() {
  final mixed = [
    _n('a', 'Fresh note'),
    _n('b', 'Old note', age: const Duration(days: 20)),
    _n('c', 'Campus news', contentType: 'news'),
  ];

  testWidgets('shows Today and Earlier sections in English', (tester) async {
    await _pump(tester, mixed);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Earlier'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('From BISO'), findsOneWidget);
  });

  testWidgets('shows the sections in Norwegian', (tester) async {
    await _pump(tester, mixed, locale: const Locale('no'));
    expect(find.text('I dag'), findsOneWidget);
    expect(find.text('Tidligere'), findsOneWidget);
    expect(find.text('Fra BISO'), findsOneWidget);
    expect(find.text('Nyheter'), findsOneWidget);
    expect(find.text('Stillinger'), findsOneWidget);
  });

  testWidgets('the News chip shows only news rows', (tester) async {
    await _pump(tester, mixed);
    expect(find.text('Fresh note'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'News'));
    await tester.pump();
    expect(find.text('Campus news'), findsOneWidget);
    expect(find.text('Fresh note'), findsNothing);
    expect(find.text('Old note'), findsNothing);
  });

  testWidgets('an unread urgent row appears above the Today section', (
    tester,
  ) async {
    await _pump(tester, [
      _n('a', 'Fresh note'),
      _n('u', 'Fire drill', category: 'urgent', age: const Duration(hours: 5)),
    ]);
    final urgentY = tester.getTopLeft(find.text('Fire drill')).dy;
    final todayY = tester.getTopLeft(find.text('Today')).dy;
    expect(urgentY, lessThan(todayY));
  });

  testWidgets('a burst row shows its count, and a mini card opens its route', (
    tester,
  ) async {
    await _pump(
      tester,
      [_n('b1', '3 new events in Bergen', items: _burstItems)],
      routes: [
        GoRoute(
          path: '/explore/events/:id',
          builder: (_, state) =>
              Text('event page ${state.pathParameters['id']}'),
        ),
      ],
    );
    expect(find.text('3 new'), findsOneWidget);
    expect(find.text('See all 3'), findsOneWidget);
    expect(find.text('Bergen event 2'), findsOneWidget);

    await tester.tap(find.text('Bergen event 2'));
    await tester.pumpAndSettle();
    expect(find.text('event page e2'), findsOneWidget);

    // Pushed, not gone to: Back returns to the inbox.
    GoRouter.of(tester.element(find.text('event page e2'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('See all 3'), findsOneWidget);
  });

  testWidgets('See all opens the announcement detail route', (tester) async {
    await _pump(
      tester,
      [_n('b1', '3 new events in Bergen', items: _burstItems)],
      routes: [
        GoRoute(
          path: '/announcements/:id',
          builder: (_, state) => Text('detail ${state.pathParameters['id']}'),
        ),
      ],
    );
    await tester.tap(find.text('See all 3'));
    await tester.pumpAndSettle();
    expect(find.text('detail b1'), findsOneWidget);

    GoRouter.of(tester.element(find.text('detail b1'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('See all 3'), findsOneWidget);
  });

  testWidgets('the announcement detail lists a burst\'s items', (tester) async {
    final burst = _n(
      'b1',
      '3 new events in Bergen',
      items: _burstItems,
      read: true,
    );
    await pumpBisoScreen(
      tester,
      const AnnouncementDetailScreen(announcementId: 'b1'),
      inShell: false,
      overrides: [
        announcementDetailProvider('b1').overrideWith((ref) async => burst),
      ],
    );
    expect(find.text('Bergen event 1'), findsOneWidget);
    expect(find.text('Bergen event 2'), findsOneWidget);
    expect(find.text('Bergen event 3'), findsOneWidget);
  });

  testWidgets(
    'an item opened from the announcement detail goes back to the detail',
    (tester) async {
      final burst = _n(
        'b1',
        '3 new events in Bergen',
        items: _burstItems,
        read: true,
      );
      await pumpBisoScreen(
        tester,
        const AnnouncementDetailScreen(announcementId: 'b1'),
        inShell: false,
        routed: true,
        extraRoutes: [
          GoRoute(
            path: '/explore/events/:id',
            builder: (_, state) =>
                Text('event page ${state.pathParameters['id']}'),
          ),
        ],
        overrides: [
          announcementDetailProvider('b1').overrideWith((ref) async => burst),
        ],
      );

      await tester.tap(find.text('Bergen event 2'));
      await tester.pumpAndSettle();
      expect(find.text('event page e2'), findsOneWidget);

      GoRouter.of(tester.element(find.text('event page e2'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Bergen event 2'), findsOneWidget);
      expect(find.text('3 new events in Bergen'), findsWidgets);
    },
  );

  for (final (locale, news, job) in [
    (const Locale('en'), 'News', 'Job'),
    (const Locale('no'), 'Nyhet', 'Stilling'),
  ]) {
    testWidgets(
      'the announcement detail labels a category-only news or job row '
      '(${locale.languageCode})',
      (tester) async {
        for (final (category, label) in [('news', news), ('job', job)]) {
          final n = _n('c1', 'Hello', category: category, read: true);
          await pumpBisoScreen(
            tester,
            const AnnouncementDetailScreen(announcementId: 'c1'),
            inShell: false,
            locale: locale,
            overrides: [
              announcementDetailProvider('c1').overrideWith((ref) async => n),
            ],
          );
          expect(
            find.widgetWithText(Chip, label),
            findsOneWidget,
            reason: category,
          );
          await tester.pumpWidget(const SizedBox());
        }
      },
    );
  }

  testWidgets('category-only news and job rows tile as news and jobs', (
    tester,
  ) async {
    await _pump(tester, [
      _n('n', 'Campus news', category: 'news'),
      _n('j', 'Open role', category: 'job'),
    ]);
    BisoIconTile tileOf(String title) => tester.widget<BisoIconTile>(
      find.descendant(
        of: find.ancestor(
          of: find.text(title),
          matching: find.byType(BisoListRow),
        ),
        matching: find.byType(BisoIconTile),
      ),
    );
    expect(tileOf('Campus news').icon, CupertinoIcons.news);
    expect(tileOf('Campus news').accent, BisoAccent.violet);
    expect(tileOf('Open role').icon, CupertinoIcons.briefcase);
    expect(tileOf('Open role').accent, BisoAccent.teal);

    final jobsChip = find.widgetWithText(ChoiceChip, 'Jobs');
    await tester.ensureVisible(jobsChip);
    await tester.pumpAndSettle();
    await tester.tap(jobsChip);
    await tester.pump();
    expect(find.text('Open role'), findsOneWidget);
    expect(find.text('Campus news'), findsNothing);
  });

  testWidgets('still builds on BisoPage, and the empty state shows', (
    tester,
  ) async {
    await _pump(tester, const []);
    expect(find.byType(BisoPage), findsOneWidget);
    expect(find.text('No notifications yet'), findsOneWidget);
    expect(find.text('Updates from BISO will appear here.'), findsOneWidget);
  });

  testWidgets('urgent rows stay above the sections under every filter', (
    tester,
  ) async {
    await _pump(tester, [
      _n('a', 'Campus news', contentType: 'news'),
      _n('u', 'Fire drill', category: 'urgent', age: const Duration(hours: 5)),
    ]);
    await tester.tap(find.widgetWithText(ChoiceChip, 'News'));
    await tester.pump();
    expect(find.text('Fire drill'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Fire drill')).dy,
      lessThan(tester.getTopLeft(find.text('Today')).dy),
    );
  });

  testWidgets('the burst strip does not overflow at large text', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: NotificationsScreen(clock: () => _now),
      ),
      inShell: false,
      overrides: _overrides([
        _n('b1', '3 new events in Bergen', items: _burstItems),
      ]),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('See all 3'), findsOneWidget);
  });

  testWidgets('the announcement detail is localized in Norwegian', (
    tester,
  ) async {
    final n = _n(
      'b1',
      'Hei',
      read: true,
    ).copyWith(createdAt: DateTime(2026, 10, 5, 9, 30));
    await pumpBisoScreen(
      tester,
      const AnnouncementDetailScreen(announcementId: 'b1'),
      inShell: false,
      locale: const Locale('no'),
      overrides: [
        announcementDetailProvider('b1').overrideWith((ref) async => n),
      ],
    );
    expect(find.text('Kunngjøring'), findsOneWidget);
    expect(find.text('Ingen innhold.'), findsOneWidget);
    expect(find.textContaining('okt'), findsOneWidget);
  });
}
