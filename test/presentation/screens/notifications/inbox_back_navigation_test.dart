import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/models/app_notification_model.dart';
import 'package:biso/data/models/inbox_item.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/main.dart';
import 'package:biso/providers/notification/notification_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Back from content opened in the inbox returns to the inbox, and from
/// content opened in an announcement to the announcement - not to the list
/// the content belongs to. The router below has the app's shape: the inbox
/// routes come from main.dart and sit inside a tab shell beside Home, with
/// the content routes nested under Explore as in the app.

class _FakeInbox extends StateNotifier<NotificationInboxState>
    implements NotificationInboxNotifier {
  _FakeInbox(super.state);

  @override
  Future<void> markRead(AppNotification notification) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _created = DateTime.now().subtract(const Duration(hours: 1));

final _burstItems = [
  for (final i in [1, 2, 3])
    InboxItem(type: 'event', id: 'e$i', titleEn: 'Bergen event $i'),
];

final _burst = AppNotification(
  id: 'b1',
  title: '3 new events in Bergen',
  body: '',
  category: 'event',
  deepLink: 'biso://announcement?id=b1',
  createdAt: _created,
  items: _burstItems,
);

final _news = AppNotification(
  id: 'n-row',
  title: 'Campus news is out',
  body: '',
  category: 'news',
  deepLink: 'biso://news?id=n1',
  createdAt: _created,
);

Widget _stub(String label) => Scaffold(body: Center(child: Text(label)));

GoRouter _router() => GoRouter(
  initialLocation: '/home',
  routes: [
    ShellRoute(
      builder: (_, _, child) =>
          Scaffold(body: child, bottomNavigationBar: const Text('TAB BAR')),
      routes: [
        GoRoute(
          path: '/home',
          // Home's bell, as premium_home_screen.dart opens the inbox.
          builder: (context, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => context.push('/notifications'),
                child: const Text('bell'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/explore',
          builder: (_, _) => _stub('explore'),
          routes: [
            GoRoute(
              path: '/events',
              builder: (_, _) => _stub('events list'),
              routes: [
                GoRoute(
                  path: '/:eventId',
                  builder: (_, state) =>
                      _stub('event page ${state.pathParameters['eventId']}'),
                ),
              ],
            ),
            GoRoute(
              path: '/news',
              builder: (_, _) => _stub('news list'),
              routes: [
                GoRoute(
                  path: '/:newsId',
                  builder: (_, state) =>
                      _stub('news page ${state.pathParameters['newsId']}'),
                ),
              ],
            ),
          ],
        ),
        ...inboxRoutes(),
      ],
    ),
  ],
);

Future<GoRouter> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final router = _router();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationInboxProvider.overrideWith(
          (ref) => _FakeInbox(NotificationInboxState(items: [_burst, _news])),
        ),
        announcementDetailProvider('b1').overrideWith((ref) async => _burst),
      ],
      child: MaterialApp.router(
        theme: PremiumTheme.build(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _openInboxFromHome(WidgetTester tester) async {
  await tester.tap(find.text('bell'));
  await tester.pumpAndSettle();
  expect(find.text('Notifications'), findsWidgets);
}

Future<void> _back(WidgetTester tester, GoRouter router) async {
  router.pop();
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  test('the inbox and announcement routes sit inside the tab shell', () {
    final shell = appRouter.configuration.routes.whereType<ShellRoute>().single;
    final shellPaths = shell.routes.whereType<GoRoute>().map((r) => r.path);
    expect(shellPaths, containsAll(['/notifications', '/announcements/:id']));

    final topLevelPaths = appRouter.configuration.routes
        .whereType<GoRoute>()
        .map((r) => r.path);
    expect(topLevelPaths, isNot(contains('/notifications')));
    expect(topLevelPaths, isNot(contains('/announcements/:id')));
  });

  testWidgets('Back from a burst card returns to the inbox, then Home', (
    tester,
  ) async {
    final router = await _pumpApp(tester);
    await _openInboxFromHome(tester);

    await tester.tap(find.text('Bergen event 2'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('event page e2'), findsOneWidget);

    await _back(tester, router);
    expect(find.text('3 new events in Bergen'), findsOneWidget);
    expect(find.text('events list'), findsNothing);

    await _back(tester, router);
    expect(find.text('bell'), findsOneWidget);
  });

  testWidgets('Back from a plain row with a news link returns to the inbox', (
    tester,
  ) async {
    final router = await _pumpApp(tester);
    await _openInboxFromHome(tester);

    await tester.tap(find.text('Campus news is out'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('news page n1'), findsOneWidget);

    await _back(tester, router);
    expect(find.text('Campus news is out'), findsOneWidget);
    expect(find.text('news list'), findsNothing);
  });

  testWidgets(
    'Back from an item opened from See all returns to the announcement, '
    'then the inbox',
    (tester) async {
      final router = await _pumpApp(tester);
      await _openInboxFromHome(tester);

      await tester.tap(find.text('See all 3'));
      await tester.pumpAndSettle();
      expect(find.text('Announcement'), findsWidgets);

      await tester.tap(find.text('Bergen event 3'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('event page e3'), findsOneWidget);

      await _back(tester, router);
      expect(find.text('Announcement'), findsWidgets);
      expect(find.text('Bergen event 3'), findsOneWidget);

      await _back(tester, router);
      expect(find.text('See all 3'), findsOneWidget);
    },
  );
}
