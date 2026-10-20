import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:biso/data/services/deep_link_service.dart';
import 'package:biso/data/services/local_notification_presenter.dart';
import 'package:biso/data/services/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _UnusedAccount extends Account {
  _UnusedAccount() : super(Client());
}

class _FakePresenter implements LocalNotificationPresenter {
  bool throwOnInitialize = false;

  final List<RemoteMessage> shown = <RemoteMessage>[];

  @override
  Future<void> initialize({
    required void Function(Map<String, dynamic> data) onTap,
  }) async {
    if (throwOnInitialize) throw StateError('invalid_icon');
  }

  @override
  Future<void> show(RemoteMessage message) async => shown.add(message);
}

NotificationService _service(_FakePresenter presenter, {bool android = true}) =>
    NotificationService.withAccount(
      _UnusedAccount(),
      presenter: presenter,
      isAndroid: () => android,
    );

RemoteMessage _message(Map<String, dynamic> data) =>
    RemoteMessage(data: data, messageId: 'm1');

void main() {
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

  group('foreground pushes', () {
    test('shows a foreground push on Android', () async {
      final presenter = _FakePresenter();
      final service = _service(presenter);
      service.handleForegroundMessage(_message({'type': 'announcement'}));
      expect(presenter.shown, hasLength(1));
    });

    test('does not show a foreground push on iOS', () async {
      final presenter = _FakePresenter();
      final service = _service(presenter, android: false);
      final emitted = <RemoteMessage>[];
      final sub = service.onForegroundMessage.listen(emitted.add);
      service.handleForegroundMessage(_message({'type': 'announcement'}));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(presenter.shown, isEmpty);
      expect(emitted, hasLength(1));
    });
  });

  test('a presenter that fails to initialize does not throw', () async {
    final presenter = _FakePresenter()..throwOnInitialize = true;
    await _service(presenter).initializeLocalPresenter();
  });

  group('tap routing', () {
    late List<String> visited;

    Future<void> pumpRouter(WidgetTester tester) async {
      visited = <String>[];
      final router = GoRouter(
        navigatorKey: navigatorKey,
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const SizedBox(),
          ),
          GoRoute(
            path: '/explore/news/:id',
            builder: (_, state) {
              visited.add(state.uri.toString());
              return const SizedBox();
            },
          ),
          GoRoute(
            path: '/explore/events/:id',
            builder: (_, state) {
              visited.add(state.uri.toString());
              return const SizedBox();
            },
          ),
          GoRoute(
            path: '/notifications',
            builder: (_, state) {
              visited.add(state.uri.toString());
              return const SizedBox();
            },
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
    }

    testWidgets('a deep_link routes to the news article', (tester) async {
      await pumpRouter(tester);
      _service(_FakePresenter()).handleNotificationTap(
        _message({
          'type': 'announcement',
          'deep_link': 'biso://news?id=n1',
        }),
      );
      await tester.pumpAndSettle();
      expect(visited, ['/explore/news/n1']);
    });

    testWidgets('content_type and content_id route to the event', (
      tester,
    ) async {
      await pumpRouter(tester);
      _service(_FakePresenter()).handleNotificationTap(
        _message({
          'type': 'announcement',
          'content_type': 'event',
          'content_id': 'e1',
          'deep_link': '',
        }),
      );
      await tester.pumpAndSettle();
      expect(visited, ['/explore/events/e1']);
    });

    test('an empty payload queues /notifications until a context exists', () {
      // No navigator is mounted: this is a cold start.
      final service = _service(_FakePresenter());
      service.handleNotificationTap(_message({'type': 'announcement'}));
      expect(DeepLinkService().pendingRoutesForTest, ['/notifications']);
    });

    testWidgets('a queued /notifications is replayed by flushPendingLinks', (
      tester,
    ) async {
      // Queued by the previous test, singleton survives.
      DeepLinkService().queueRoute('/notifications');
      await pumpRouter(tester);
      DeepLinkService().flushPendingLinks();
      await tester.pumpAndSettle();
      expect(visited, contains('/notifications'));
      expect(DeepLinkService().pendingRoutesForTest, isEmpty);
    });
  });
}
