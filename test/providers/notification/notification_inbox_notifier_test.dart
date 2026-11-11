import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appwrite/appwrite.dart';
import 'package:biso/data/models/app_notification_model.dart';
import 'package:biso/data/services/notification_inbox_service.dart';
import 'package:biso/data/services/notification_service.dart';
import 'package:biso/providers/notification/notification_provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/provider_retry.dart';
import 'package:biso/providers/ui/locale_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 10, 20, 12);

/// Notification [id], [hoursOld] hours old, so a list of them sorts by age.
AppNotification _n(String id, {int hoursOld = 0, bool read = false}) =>
    AppNotification(
      id: id,
      title: id,
      body: '',
      category: 'general',
      createdAt: _now.subtract(Duration(hours: hoursOld)),
      read: read,
    );

/// Student `u`, at campus `2`.
class _Student extends Notifier<AuthState> implements AuthNotifier {
  @override
  AuthState build() => const AuthState(
    isAuthenticated: true,
    user: UserModel(id: 'u', name: 'U', email: 'u@bi.no', campusId: '2'),
  );

  /// What [AuthNotifier.updateProfile] does to the state around a save: the
  /// same student, loading and then not.
  void saveProfile() {
    state = state.copyWith(isLoading: true);
    state = state.copyWith(isLoading: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The app in English.
class _English extends Notifier<ui.Locale> implements LocaleNotifier {
  @override
  ui.Locale build() => const ui.Locale('en');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The server, as far as the inbox can tell: [server] is what a fetch
/// returns, and a read or clear that succeeds changes it. Fetches and writes
/// can be held, so a test decides the order their responses arrive in.
class _FakeInboxService extends NotificationInboxService {
  List<AppNotification> server = [];

  /// When set, the next fetch snapshots [server] as it is when it is made,
  /// then waits for this before answering.
  Completer<void>? holdNextFetch;

  /// When set, every read and clear waits for this before it lands.
  Completer<void>? holdWrites;

  bool failReads = false;
  Set<String> failClearIds = {};
  bool clearThrows = false;

  final List<String> readCalls = [];
  final List<List<String>> clearCalls = [];
  int fetchCount = 0;

  @override
  Future<List<AppNotification>> fetchInbox({
    required String userId,
    required String locale,
    required String? campusId,
    Map<String, bool> topicIntent = const {},
    DateTime? joinedAt,
  }) async {
    fetchCount++;
    final snapshot = List.of(server);
    final hold = holdNextFetch;
    holdNextFetch = null;
    if (hold != null) await hold.future;
    return snapshot;
  }

  @override
  Future<void> markAsRead(String announcementId) async {
    readCalls.add(announcementId);
    final hold = holdWrites;
    if (hold != null) await hold.future;
    if (failReads) throw NotificationInboxException('down');
    server = [
      for (final n in server)
        n.id == announcementId ? n.copyWith(read: true) : n,
    ];
  }

  @override
  Future<Set<String>> clear(List<String> announcementIds) async {
    clearCalls.add(List.of(announcementIds));
    final hold = holdWrites;
    if (hold != null) await hold.future;
    if (clearThrows) throw StateError('unexpected');
    final failed = announcementIds.where(failClearIds.contains).toSet();
    server = [
      for (final n in server)
        if (!announcementIds.contains(n.id) || failed.contains(n.id)) n,
    ];
    return failed;
  }

  @override
  RealtimeSubscription subscribe({required void Function() onChange}) =>
      RealtimeSubscription(
        close: () async {},
        unsubscribe: () async {},
        update: ({List<Object>? channels, List<String>? queries}) async {},
        channels: const [],
        queries: const [],
        controller: StreamController<RealtimeMessage>(),
      );
}

/// No topic opt-outs and no foreground pushes.
class _QuietNotificationService extends NotificationService {
  _QuietNotificationService() : super.withAccount(Account(Client()));

  @override
  Future<Map<String, bool>> loadTopicIntent() async => const {};

  @override
  Stream<RemoteMessage> get onForegroundMessage => const Stream.empty();
}

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

  late _FakeInboxService service;

  setUp(() {
    service = _FakeInboxService()
      ..server = [_n('a'), _n('b', hoursOld: 1), _n('c', hoursOld: 2)];
  });

  late ProviderContainer container;

  /// The notifier once its first load has landed.
  Future<NotificationInboxNotifier> loaded() async {
    container = ProviderContainer(
      retry: noAutomaticRetry,
      overrides: [
        notificationInboxServiceProvider.overrideWithValue(service),
        notificationServiceProvider.overrideWithValue(
          _QuietNotificationService(),
        ),
        authStateProvider.overrideWith(_Student.new),
        localeProvider.overrideWith(_English.new),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(notificationInboxProvider.notifier);
    await pumpEventQueue();
    return notifier;
  }

  List<String> ids(NotificationInboxNotifier notifier) => [
    for (final n in notifier.state.items) n.id,
  ];

  AppNotification item(NotificationInboxNotifier notifier, String id) =>
      notifier.state.items.firstWhere((n) => n.id == id);

  test(
    'markRead shows the row read at once and keeps it read once saved',
    () async {
      final notifier = await loaded();

      final saving = notifier.markRead(item(notifier, 'a'));

      expect(item(notifier, 'a').read, isTrue);
      await saving;
      await notifier.refresh();
      expect(item(notifier, 'a').read, isTrue);
      expect(service.readCalls, ['a']);
    },
  );

  test(
    'a failed markRead puts the row back to unread without setting an error',
    () async {
      service.failReads = true;
      final notifier = await loaded();
      expect(notifier.state.unreadCount, 3);

      await notifier.markRead(item(notifier, 'a'));

      expect(item(notifier, 'a').read, isFalse);
      expect(notifier.state.unreadCount, 3);
      expect(notifier.state.error, isNull);
    },
  );

  test(
    'clear removes the rows before its first await and resolves true once saved',
    () async {
      final notifier = await loaded();

      final clearing = notifier.clear(['a']);

      expect(ids(notifier), ['b', 'c']);
      expect(await clearing, isTrue);
      await notifier.refresh();
      expect(ids(notifier), ['b', 'c']);
    },
  );

  test(
    'a failed clear puts the rows back in their old places and resolves false',
    () async {
      service.failClearIds = {'b'};
      final notifier = await loaded();

      expect(await notifier.clear(['b']), isFalse);

      expect(ids(notifier), ['a', 'b', 'c']);
    },
  );

  test('a clear that throws puts every row back', () async {
    service.clearThrows = true;
    final notifier = await loaded();

    expect(await notifier.clear(['a', 'b']), isFalse);

    expect(ids(notifier), ['a', 'b', 'c']);
  });

  test(
    'a refresh landing while a clear is in flight keeps the rows hidden',
    () async {
      final notifier = await loaded();
      final hold = service.holdWrites = Completer<void>();

      final clearing = notifier.clear(['a']);
      await notifier.refresh();

      expect(ids(notifier), ['b', 'c']);
      hold.complete();
      expect(await clearing, isTrue);
      expect(ids(notifier), ['b', 'c']);
    },
  );

  test(
    'a refresh fetched before a clear succeeded keeps the rows hidden when it '
    'lands after',
    () async {
      final notifier = await loaded();
      final fetch = service.holdNextFetch = Completer<void>();

      final refreshing = notifier.refresh();
      expect(await notifier.clear(['a']), isTrue);
      fetch.complete();
      await refreshing;

      expect(ids(notifier), ['b', 'c']);
    },
  );

  test(
    'a refresh landing while a read is in flight keeps the row read',
    () async {
      final notifier = await loaded();
      final hold = service.holdWrites = Completer<void>();

      final saving = notifier.markRead(item(notifier, 'a'));
      await notifier.refresh();

      expect(item(notifier, 'a').read, isTrue);
      hold.complete();
      await saving;
      expect(item(notifier, 'a').read, isTrue);
    },
  );

  test("only the failed batch's rows come back", () async {
    service.failClearIds = {'a', 'c'};
    final notifier = await loaded();

    expect(await notifier.clear(['a', 'b', 'c']), isFalse);

    expect(ids(notifier), ['a', 'c']);
  });

  test(
    'a profile save while a clear is on its way does not bring the row back: '
    'the inbox is still for the same student, so it keeps what it is saving',
    () async {
      final notifier = await loaded();
      final hold = service.holdWrites = Completer<void>();
      final clearing = notifier.clear(['b']);
      expect(ids(notifier), ['a', 'c']);

      (container.read(authStateProvider.notifier) as _Student).saveProfile();
      container.read(notificationInboxProvider);
      await pumpEventQueue(); // a fetch, if the save set one off

      expect(ids(notifier), ['a', 'c']);
      hold.complete();
      expect(await clearing, isTrue);
      expect(ids(notifier), ['a', 'c']);
    },
  );

  test(
    'disposing while a read or clear is in flight writes no state and throws '
    'nothing',
    () async {
      final notifier = await loaded();
      final hold = service.holdWrites = Completer<void>();
      service
        ..failReads = true
        ..failClearIds = {'b'};

      final saving = notifier.markRead(item(notifier, 'a'));
      final clearing = notifier.clear(['b']);
      container.dispose();
      hold.complete();

      await expectLater(saving, completes);
      await expectLater(clearing, completes);
    },
  );

  test('refreshes that overlap end with what the server holds last, and run '
      'at most one more fetch', () async {
    final notifier = await loaded();
    final before = service.fetchCount;
    final first = service.holdNextFetch = Completer<void>();

    final r1 = notifier.refresh();
    await pumpEventQueue(); // r1's fetch is out, and held
    // Another device clears 'a', and the realtime events arrive.
    service.server = [_n('b', hoursOld: 1), _n('c', hoursOld: 2)];
    final r2 = notifier.refresh();
    final r3 = notifier.refresh();
    await pumpEventQueue();
    first.complete();
    await Future.wait([r1, r2, r3]);

    expect(ids(notifier), ['b', 'c']);
    expect(service.fetchCount - before, 2);
  });

  test('unreadCount never counts a cleared notification', () async {
    final notifier = await loaded();
    expect(notifier.state.unreadCount, 3);

    final clearing = notifier.clear(['a']);
    expect(notifier.state.unreadCount, 2);
    await clearing;
    await notifier.refresh();

    expect(notifier.state.unreadCount, 2);
  });
}
