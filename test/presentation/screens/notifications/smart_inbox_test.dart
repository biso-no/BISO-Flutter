import 'dart:convert';

import 'package:biso/data/models/app_notification_model.dart';
import 'package:biso/data/models/inbox_item.dart';
import 'package:biso/presentation/screens/notifications/announcement_detail_screen.dart';
import 'package:biso/presentation/screens/notifications/notifications_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/notification/inbox_opened_items_provider.dart';
import 'package:biso/providers/notification/notification_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

const _student = 'u1';

/// Opened burst items, as the student signed in as [_student] left them.
void _openedBefore(Map<String, List<String>> opened) =>
    SharedPreferences.setMockInitialValues(<String, Object>{
      'inbox_opened_items_$_student': jsonEncode(opened),
    });

Override _openedItems() => inboxOpenedItemsProvider.overrideWith(
  (ref) => InboxOpenedItemsNotifier(userId: _student),
);

List<Override> _overrides(List<AppNotification> items, {_FakeInbox? inbox}) => [
  notificationInboxProvider.overrideWith(
    (ref) => inbox ?? _FakeInbox(NotificationInboxState(items: items)),
  ),
  _openedItems(),
];

Future<void> _pump(
  WidgetTester tester,
  List<AppNotification> items, {
  Locale? locale,
  List<RouteBase> routes = const [],
  _FakeInbox? inbox,
}) => pumpBisoScreen(
  tester,
  NotificationsScreen(clock: () => _now),
  inShell: false,
  routed: routes.isNotEmpty,
  extraRoutes: routes,
  locale: locale,
  overrides: _overrides(items, inbox: inbox),
);

Future<void> _pumpDetail(
  WidgetTester tester,
  AppNotification announcement, {
  Locale? locale,
  List<RouteBase> routes = const [],
}) => pumpBisoScreen(
  tester,
  AnnouncementDetailScreen(announcementId: announcement.id),
  inShell: false,
  routed: routes.isNotEmpty,
  extraRoutes: routes,
  locale: locale,
  overrides: [
    announcementDetailProvider(
      announcement.id,
    ).overrideWith((ref) async => announcement),
    _openedItems(),
  ],
);

GoRoute _eventPage() => GoRoute(
  path: '/explore/events/:id',
  builder: (_, state) => Text('event page ${state.pathParameters['id']}'),
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

/// Taps the filter chip labelled [label], scrolling it out from under the
/// "Clear all" link first.
Future<void> _tapChip(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(ChoiceChip, label);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

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
    await _tapChip(tester, 'News');
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
        _openedItems(),
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
          _openedItems(),
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
              _openedItems(),
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
    expect(find.text("You're all caught up"), findsOneWidget);
    expect(find.text('Updates from BISO will appear here.'), findsOneWidget);
  });

  testWidgets('urgent rows stay above the sections under every filter', (
    tester,
  ) async {
    await _pump(tester, [
      _n('a', 'Campus news', contentType: 'news'),
      _n('u', 'Fire drill', category: 'urgent', age: const Duration(hours: 5)),
    ]);
    await _tapChip(tester, 'News');
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
        _openedItems(),
      ],
    );
    expect(find.text('Kunngjøring'), findsOneWidget);
    expect(find.text('Ingen innhold.'), findsOneWidget);
    expect(find.textContaining('okt'), findsOneWidget);
  });

  group('opened burst cards leave the group', () {
    final burst = _n('b1', '3 new events in Bergen', items: _burstItems);

    testWidgets('one of three opened: two cards, 2 new, See all 3', (
      tester,
    ) async {
      _openedBefore({
        'b1': ['e2'],
      });
      await _pump(tester, [burst]);
      expect(find.text('Bergen event 1'), findsOneWidget);
      expect(find.text('Bergen event 2'), findsNothing);
      expect(find.text('Bergen event 3'), findsOneWidget);
      expect(find.text('2 new'), findsOneWidget);
      expect(find.text('See all 3'), findsOneWidget);
    });

    testWidgets('all opened: no cards, the row stays', (tester) async {
      _openedBefore({
        'b1': ['e1', 'e2', 'e3'],
      });
      await _pump(tester, [burst.copyWith(read: true)]);
      expect(find.text('3 new events in Bergen'), findsOneWidget);
      for (final i in [1, 2, 3]) {
        expect(find.text('Bergen event $i'), findsNothing);
      }
      expect(find.textContaining('new'), findsOneWidget); // the title only
      expect(find.text('See all 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('items opened in another announcement do not count', (
      tester,
    ) async {
      _openedBefore({
        'other': ['e1', 'e2'],
      });
      await _pump(tester, [burst]);
      expect(find.text('3 new'), findsOneWidget);
      expect(find.text('Bergen event 1'), findsOneWidget);
    });

    testWidgets(
      'a tapped card is marked opened and read, and has left the strip on Back',
      (tester) async {
        final inbox = _FakeInbox(NotificationInboxState(items: [burst]));
        await _pump(tester, [burst], inbox: inbox, routes: [_eventPage()]);

        await tester.tap(find.text('Bergen event 2'));
        await tester.pumpAndSettle();
        expect(find.text('event page e2'), findsOneWidget);
        expect(inbox.marked, ['b1']);

        GoRouter.of(tester.element(find.text('event page e2'))).pop();
        await tester.pumpAndSettle();
        expect(find.text('Bergen event 2'), findsNothing);
        expect(find.text('Bergen event 1'), findsOneWidget);
        expect(find.text('2 new'), findsOneWidget);
        expect(find.text('See all 3'), findsOneWidget);

        final prefs = await SharedPreferences.getInstance();
        expect(jsonDecode(prefs.getString('inbox_opened_items_$_student')!), {
          'b1': ['e2'],
        });
      },
    );

    for (final (locale, opened) in [
      (const Locale('en'), 'Opened'),
      (const Locale('no'), 'Åpnet'),
    ]) {
      testWidgets('the detail lists every item, an opened one muted '
          '(${locale.languageCode})', (tester) async {
        _openedBefore({
          'b1': ['e2'],
        });
        final semantics = tester.ensureSemantics();
        await _pumpDetail(tester, burst.copyWith(read: true), locale: locale);

        for (final i in [1, 2, 3]) {
          expect(find.text('Bergen event $i'), findsOneWidget);
        }
        final palette = BisoPalette.of(
          tester.element(find.text('Bergen event 2')),
        );
        Color? titleColor(String title) =>
            tester.widget<Text>(find.text(title)).style?.color;
        expect(titleColor('Bergen event 2'), palette.muted);
        expect(titleColor('Bergen event 1'), palette.ink);
        expect(find.byIcon(CupertinoIcons.checkmark_alt), findsOneWidget);

        String rowLabel(String title) => tester
            .getSemantics(
              find.ancestor(
                of: find.text(title),
                matching: find.byType(BisoListRow),
              ),
            )
            .label;
        expect(rowLabel('Bergen event 2'), contains(opened));
        expect(rowLabel('Bergen event 1'), isNot(contains(opened)));
        semantics.dispose();
      });
    }

    testWidgets('an item opened from the detail is marked opened there', (
      tester,
    ) async {
      await _pumpDetail(
        tester,
        burst.copyWith(read: true),
        routes: [_eventPage()],
      );
      expect(find.byIcon(CupertinoIcons.checkmark_alt), findsNothing);

      await tester.tap(find.text('Bergen event 3'));
      await tester.pumpAndSettle();
      expect(find.text('event page e3'), findsOneWidget);

      GoRouter.of(tester.element(find.text('event page e3'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Bergen event 3'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.checkmark_alt), findsOneWidget);
      final palette = BisoPalette.of(
        tester.element(find.text('Bergen event 3')),
      );
      expect(
        tester.widget<Text>(find.text('Bergen event 3')).style?.color,
        palette.muted,
      );
    });
  });
}
