import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/auth_service.dart';
import 'package:biso/data/services/device_subscription_store.dart';
import 'package:biso/data/services/notification_service.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/notification/notification_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Appwrite, as far as this device's account is concerned: its push targets,
/// and the topic subscribers attached to them.
class _FakeServer {
  /// Target id -> the FCM token it is bound to.
  final Map<String, String> targets = <String, String>{};

  /// Subscriber id -> the topic and target it belongs to.
  final Map<String, ({String topicId, String targetId})> subscribers =
      <String, ({String topicId, String targetId})>{};

  int _issued = 0;
  String nextId(String prefix) => '$prefix-${++_issued}';

  /// Deletes [targetId] and, as Appwrite does, every subscriber attached to
  /// it. Reports whether there was such a target.
  bool removeTarget(String targetId) {
    if (targets.remove(targetId) == null) return false;
    subscribers.removeWhere((_, s) => s.targetId == targetId);
    return true;
  }
}

models.Target _target({required String id, required String identifier}) =>
    models.Target(
      $id: id,
      $createdAt: '',
      $updatedAt: '',
      name: 'device',
      userId: 'user-1',
      providerId: 'push',
      providerType: 'push',
      identifier: identifier,
      expired: false,
    );

models.Subscriber _subscriber({
  required String id,
  required String topicId,
  required String targetId,
}) => models.Subscriber(
  $id: id,
  $createdAt: '',
  $updatedAt: '',
  targetId: targetId,
  target: _target(id: targetId, identifier: ''),
  userId: 'user-1',
  userName: 'Test',
  topicId: topicId,
  providerType: 'push',
);

class _FakeAccount extends Account {
  _FakeAccount(this.server) : super(Client());

  final _FakeServer server;

  /// The student's topic intent, as their account preferences hold it.
  Map<String, bool> intent = const <String, bool>{
    'news': true,
    'events': false,
    'jobs': false,
    'shop': false,
  };

  /// When set, [deletePushTarget] throws it instead of deleting.
  AppwriteException? deleteTargetThrows;

  /// [deletePushTarget] calls, by number (counting from 1), that wait for
  /// their completer before doing anything.
  final Map<int, Completer<void>> holdDeleteTarget = <int, Completer<void>>{};

  int deleteTargetCalls = 0;
  int updateTargetCalls = 0;
  int createTargetCalls = 0;

  @override
  Future deletePushTarget({required String targetId}) async {
    final call = ++deleteTargetCalls;
    final hold = holdDeleteTarget[call];
    if (hold != null) await hold.future;
    final failure = deleteTargetThrows;
    if (failure != null) throw failure;
    if (!server.removeTarget(targetId)) {
      throw AppwriteException('target not found', 404);
    }
  }

  @override
  Future<models.Target> updatePushTarget({
    required String targetId,
    required String identifier,
  }) async {
    updateTargetCalls++;
    if (!server.targets.containsKey(targetId)) {
      throw AppwriteException('target not found', 404);
    }
    server.targets[targetId] = identifier;
    return _target(id: targetId, identifier: identifier);
  }

  @override
  Future<models.Target> createPushTarget({
    required String targetId,
    required String identifier,
    String? providerId,
  }) async {
    createTargetCalls++;
    final id = server.nextId('new-target');
    server.targets[id] = identifier;
    return _target(id: id, identifier: identifier);
  }

  @override
  Future<models.Preferences> getPrefs() async => models.Preferences(
    data: <String, dynamic>{
      'notification_topics': Map<String, dynamic>.from(intent),
    },
  );
}

class _FakeMessaging extends Messaging {
  _FakeMessaging(this.server) : super(Client());

  final _FakeServer server;

  /// [createSubscriber] calls, by number (counting from 1), that wait for
  /// their completer before the server sees them: a request still on its
  /// way, holding its run mid-flight.
  final Map<int, Completer<void>> holdCreateRequest = <int, Completer<void>>{};

  /// [createSubscriber] calls, by number, that the server carries out at
  /// once but whose answer waits for the completer: a subscribe that has
  /// landed, and whose response is late.
  final Map<int, Completer<void>> holdCreateResponse =
      <int, Completer<void>>{};

  /// [deleteSubscriber] calls, by number, that the server carries out at
  /// once but whose answer waits for the completer.
  final Map<int, Completer<void>> holdDeleteResponse =
      <int, Completer<void>>{};

  /// When set, [deleteSubscriber] throws it instead of deleting.
  AppwriteException? deleteThrows;

  int createCalls = 0;
  int deleteCalls = 0;

  @override
  Future<models.Subscriber> createSubscriber({
    required String topicId,
    required String subscriberId,
    required String targetId,
  }) async {
    final call = ++createCalls;
    final request = holdCreateRequest[call];
    if (request != null) await request.future;
    if (!server.targets.containsKey(targetId)) {
      throw AppwriteException('target not found', 404);
    }
    final alreadyHeld = server.subscribers.values.any(
      (s) => s.topicId == topicId && s.targetId == targetId,
    );
    if (alreadyHeld) {
      throw AppwriteException('subscriber already exists', 409);
    }
    final id = server.nextId('new-sub');
    server.subscribers[id] = (topicId: topicId, targetId: targetId);
    final response = holdCreateResponse[call];
    if (response != null) await response.future;
    return _subscriber(id: id, topicId: topicId, targetId: targetId);
  }

  @override
  Future deleteSubscriber({
    required String topicId,
    required String subscriberId,
  }) async {
    final call = ++deleteCalls;
    final failure = deleteThrows;
    if (failure != null) throw failure;
    if (server.subscribers[subscriberId]?.topicId != topicId) {
      throw AppwriteException('subscriber not found', 404);
    }
    server.subscribers.remove(subscriberId);
    final response = holdDeleteResponse[call];
    if (response != null) await response.future;
  }
}

/// The real [NotificationService] — its queue, `reconcile`, `clearToken` and
/// `resolvePushTarget` — with only the Firebase calls stood in for.
class _DeviceService extends NotificationService {
  _DeviceService(
    super.account,
    _FakeMessaging messaging, {
    super.store,
  }) : super.withAccount(messaging: messaging);

  /// This device's FCM token. [deletePlatformToken] replaces it, as Firebase
  /// issues a fresh token once the old one is deleted.
  String token = 'token-1';
  int _tokensIssued = 1;

  /// When set, [deletePlatformToken] throws it instead of invalidating
  /// [token].
  Object? deleteTokenThrows;

  int deleteTokenCalls = 0;

  @override
  Future<bool> checkPlatformPermission() async => true;

  @override
  Future<String?> fetchPlatformToken() async => token;

  @override
  Future<void> deletePlatformToken() async {
    deleteTokenCalls++;
    final failure = deleteTokenThrows;
    if (failure != null) throw failure;
    token = 'token-${++_tokensIssued}';
  }
}

/// A store whose every read and write throws.
class _BrokenStore extends DeviceSubscriptionStore {
  Never _fail() => throw StateError('storage unavailable');

  @override
  Future<String?> readTargetId() async => _fail();

  @override
  Future<void> writeTargetId(String targetId) async => _fail();

  @override
  Future<Map<String, String>> readSubscriberIds() async => _fail();

  @override
  Future<bool> setSubscriberIdIfAbsent(
    String topicId,
    String subscriberId, {
    required String targetId,
  }) async => _fail();

  @override
  Future<bool> removeSubscriberIdIfMatches(
    String topicId,
    String subscriberId,
  ) async => _fail();

  @override
  Future<bool> readPendingTokenInvalidation() async => _fail();

  @override
  Future<void> writePendingTokenInvalidation() async => _fail();

  @override
  Future<void> clear() async => _fail();
}

/// Finds nobody signed in without a network call, and cannot delete a
/// session: a sign-out with the network down.
class _SessionKeepingAuthService extends AuthService {
  @override
  Future<UserModel?> getCurrentUser() async => null;

  @override
  Future<void> logout() async => throw Exception('Network error occurred');
}

/// An [AuthNotifier] a test signs a student in to directly, whose sign-outs
/// cannot delete the session.
class _SessionKeepingAuthNotifier extends AuthNotifier {
  _SessionKeepingAuthNotifier(NotificationService service)
    : super(_SessionKeepingAuthService(), notificationService: service);

  void signIn(String studentId, {required String campusId}) {
    state = AuthState(
      user: UserModel(
        id: studentId,
        name: studentId,
        email: '$studentId@bi.no',
        campusId: campusId,
      ),
      isAuthenticated: true,
      hasProfile: true,
      isProfileComplete: true,
    );
  }
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

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  const storedIds = <String, String>{
    'general': 'sub-general',
    'news_oslo': 'sub-news',
  };

  /// A device that has reconciled before: its target and subscribers exist on
  /// the server, bound to `token-1`, and their ids are stored locally.
  _FakeServer registeredDevice() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'push_target_id': 'target-1',
      'topic_subscriber_ids': jsonEncode(storedIds),
    });
    return _FakeServer()
      ..targets['target-1'] = 'token-1'
      ..subscribers['sub-general'] = (topicId: 'general', targetId: 'target-1')
      ..subscribers['sub-news'] = (topicId: 'news_oslo', targetId: 'target-1');
  }

  final store = DeviceSubscriptionStore();

  group('clearToken', () {
    test(
      'keeps the stored ids and records a pending token invalidation when '
      'neither the target deletion nor deleteToken() succeeds: the target is '
      'still bound to a live token, so this device keeps receiving the '
      'signed-out student\'s pushes - and clearing the ids unconditionally '
      'erased the only record of what was left to clean up',
      () async {
        final server = registeredDevice();
        final account = _FakeAccount(server)
          ..deleteTargetThrows = AppwriteException('offline', 0);
        final messaging = _FakeMessaging(server)
          ..deleteThrows = AppwriteException('offline', 0);
        final service = _DeviceService(account, messaging)
          ..deleteTokenThrows = Exception('SERVICE_NOT_AVAILABLE');

        await service.clearToken();

        expect(await store.readSubscriberIds(), storedIds);
        expect(await store.readTargetId(), 'target-1');
        expect(await store.readPendingTokenInvalidation(), isTrue);
      },
    );

    test(
      'clears the stored ids, with nothing left pending, once the push target '
      'is deleted - even though deleteToken() failed: deleting the target '
      'kills its subscribers, so nothing on the server reaches this device',
      () async {
        final server = registeredDevice();
        final service = _DeviceService(
          _FakeAccount(server),
          _FakeMessaging(server),
        )..deleteTokenThrows = Exception('SERVICE_NOT_AVAILABLE');

        await service.clearToken();

        expect(server.targets, isEmpty);
        expect(await store.readSubscriberIds(), isEmpty);
        expect(await store.readTargetId(), isNull);
        expect(await store.readPendingTokenInvalidation(), isFalse);
      },
    );

    test(
      'clears the stored ids, with nothing left pending, once deleteToken() '
      'succeeds - even though the target deletion failed: the target is left '
      'bound to a token that no longer reaches this device',
      () async {
        final server = registeredDevice();
        final account = _FakeAccount(server)
          ..deleteTargetThrows = AppwriteException('offline', 0);
        final messaging = _FakeMessaging(server)
          ..deleteThrows = AppwriteException('offline', 0);
        final service = _DeviceService(account, messaging);

        await service.clearToken();

        expect(service.deleteTokenCalls, 1);
        expect(await store.readSubscriberIds(), isEmpty);
        expect(await store.readTargetId(), isNull);
        expect(await store.readPendingTokenInvalidation(), isFalse);
      },
    );

    test(
      'completes, and still invalidates the token, when the store can be '
      'neither read nor written - no storage failure may block sign-out',
      () async {
        final server = registeredDevice();
        final service = _DeviceService(
          _FakeAccount(server),
          _FakeMessaging(server),
          store: _BrokenStore(),
        );

        await service.clearToken();

        expect(service.deleteTokenCalls, 1);
      },
    );
  });

  group('a pending token invalidation', () {
    test(
      'is retried at the next start, and until it succeeds no push target is '
      'resolved or created with the stale token - otherwise the next student '
      'to sign in gets a target of their own bound to the same token, and '
      'this device receives both students\' pushes. Once it succeeds, the '
      'stale ids are dropped and the fresh token is used',
      () async {
        final server = registeredDevice();
        final signingOut =
            _DeviceService(
                _FakeAccount(server)
                  ..deleteTargetThrows = AppwriteException('offline', 0),
                _FakeMessaging(server)
                  ..deleteThrows = AppwriteException('offline', 0),
              )
              ..deleteTokenThrows = Exception('SERVICE_NOT_AVAILABLE');
        await signingOut.clearToken();

        // The next start. Firebase still cannot delete the token.
        final account = _FakeAccount(server);
        final restarted = _DeviceService(account, _FakeMessaging(server))
          ..deleteTokenThrows = Exception('SERVICE_NOT_AVAILABLE');
        await restarted.retryPendingTokenInvalidation();
        expect(restarted.deleteTokenCalls, 1, reason: 'retried at launch');

        // The next student signs in, and the launch reconciler runs.
        expect(
          await restarted.reconcile(campusId: '2'),
          ReconcileOutcome.unavailable,
        );
        expect(restarted.deleteTokenCalls, 2, reason: 'retried again first');
        expect(account.updateTargetCalls, 0);
        expect(account.createTargetCalls, 0);
        expect(await store.readPendingTokenInvalidation(), isTrue);
        expect(await store.readSubscriberIds(), storedIds);

        // Firebase recovers.
        restarted.deleteTokenThrows = null;
        expect(
          await restarted.reconcile(campusId: '2'),
          ReconcileOutcome.applied,
        );

        expect(await store.readPendingTokenInvalidation(), isFalse);
        expect(
          account.updateTargetCalls,
          0,
          reason: 'the stale target id is dropped with the stale ids, so the '
              'fresh token is never bound to the signed-out account\'s target',
        );
        expect(account.createTargetCalls, 1);
        final newTarget = await store.readTargetId();
        expect(newTarget, isNot('target-1'));
        expect(server.targets[newTarget], restarted.token);
        expect(restarted.token, isNot('token-1'));
        expect(await store.readSubscriberIds(), {
          for (final entry in server.subscribers.entries)
            if (entry.value.targetId == newTarget)
              entry.value.topicId: entry.key,
        });
      },
    );

    test(
      'is cleared, along with the stale ids, by a successful retry at launch '
      '- before anyone signs in. Deleting the stale target is attempted '
      'first, and its id is dropped even though, with no session, that fails',
      () async {
        final server = registeredDevice();
        await (_DeviceService(
          _FakeAccount(server)
            ..deleteTargetThrows = AppwriteException('offline', 0),
          _FakeMessaging(server),
        )..deleteTokenThrows = Exception('SERVICE_NOT_AVAILABLE')).clearToken();
        expect(await store.readPendingTokenInvalidation(), isTrue);

        final account = _FakeAccount(server)
          ..deleteTargetThrows = AppwriteException('no session', 401);
        final restarted = _DeviceService(account, _FakeMessaging(server));
        await restarted.retryPendingTokenInvalidation();

        expect(restarted.deleteTokenCalls, 1);
        expect(account.deleteTargetCalls, 1, reason: 'attempted');
        expect(server.targets, contains('target-1'), reason: 'and refused');
        expect(await store.readPendingTokenInvalidation(), isFalse);
        expect(await store.readSubscriberIds(), isEmpty);
        expect(await store.readTargetId(), isNull);
        expect(account.updateTargetCalls + account.createTargetCalls, 0);
      },
    );

    test(
      'deletes the push target a failed sign-out left behind, with its '
      'subscribers, once the retried invalidation succeeds and before its id '
      'is dropped: a student who stayed signed in after the failed sign-out '
      'used to keep that target and its subscribers on their own account',
      () async {
        final server = registeredDevice();
        final account = _FakeAccount(server)
          ..deleteTargetThrows = AppwriteException('offline', 0);
        final messaging = _FakeMessaging(server)
          ..deleteThrows = AppwriteException('offline', 0);
        final service = _DeviceService(account, messaging)
          ..deleteTokenThrows = Exception('SERVICE_NOT_AVAILABLE');
        // Nothing of the sign-out gets through, deleting the session
        // included, so the student stays signed in.
        await service.clearToken();
        expect(await store.readPendingTokenInvalidation(), isTrue);

        // The network comes back, and their device reconciles again.
        account.deleteTargetThrows = null;
        messaging.deleteThrows = null;
        service.deleteTokenThrows = null;
        expect(
          await service.reconcile(campusId: '1'),
          ReconcileOutcome.applied,
        );

        expect(server.targets, isNot(contains('target-1')));
        expect(
          server.subscribers.values.map((s) => s.targetId),
          everyElement(isNot('target-1')),
        );
        final targetId = await store.readTargetId();
        expect(server.targets.keys, [targetId]);
        expect((await store.readSubscriberIds()).keys, {
          'general',
          'news_oslo',
          'news_national',
        });
      },
    );

    test(
      'a reconcile held back by it logs so, in words of its own: it reports '
      'unavailable, as any reconcile that cannot run does, and without that '
      'line a device stuck behind the marker looks no different in the logs '
      'from one that is merely offline',
      () async {
        final logs = <String>[];
        final printToConsole = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) logs.add(message);
        };
        addTearDown(() => debugPrint = printToConsole);
        const blocked = 'reconcile: blocked by a pending token invalidation';

        final server = registeredDevice();
        final service = _DeviceService(
          _FakeAccount(server)
            ..deleteTargetThrows = AppwriteException('offline', 0),
          _FakeMessaging(server)
            ..deleteThrows = AppwriteException('offline', 0),
        )..deleteTokenThrows = Exception('SERVICE_NOT_AVAILABLE');
        await service.clearToken();

        logs.clear();
        expect(
          await service.reconcile(campusId: '1'),
          ReconcileOutcome.unavailable,
        );
        expect(logs, anyElement(startsWith(blocked)));

        service.deleteTokenThrows = null;
        logs.clear();
        expect(
          await service.reconcile(campusId: '1'),
          ReconcileOutcome.applied,
        );
        expect(logs, isNot(anyElement(startsWith(blocked))));
      },
    );
  });

  group('the queue', () {
    testWidgets(
      'clearToken() abandons a reconcile in progress and cleans up at once, '
      'instead of queueing behind it: queued, the cleanup waited up to '
      'kNotificationRunTimeout, while sign-out deleted the session it needs '
      'at kSignOutCleanupTimeout. The abandoned reconcile\'s subscribe that '
      'answers afterwards is not recorded, since the store it would record '
      'into has been cleared',
      (tester) async {
        final server = _FakeServer();
        final account = _FakeAccount(server);
        final messaging = _FakeMessaging(server);
        // Its first subscribe lands on the server; the answer is held.
        final lateAnswer = messaging.holdCreateResponse[1] = Completer<void>();
        final service = _DeviceService(account, messaging);

        ReconcileOutcome? outcome;
        unawaited(service.reconcile(campusId: '1').then((o) => outcome = o));
        await tester.pump();
        expect(server.targets, hasLength(1));
        expect(server.subscribers, hasLength(1));

        var cleanedUp = false;
        unawaited(service.clearToken().then((_) => cleanedUp = true));
        await tester.pump(); // no time passes

        expect(outcome, ReconcileOutcome.unavailable);
        expect(cleanedUp, isTrue);
        expect(account.deleteTargetCalls, 1);
        expect(server.targets, isEmpty);
        expect(server.subscribers, isEmpty);
        expect(await store.readTargetId(), isNull);
        expect(await store.readSubscriberIds(), isEmpty);
        expect(await store.readPendingTokenInvalidation(), isFalse);

        lateAnswer.complete();
        await tester.pump();
        expect(await store.readSubscriberIds(), isEmpty);
        expect(
          messaging.createCalls,
          1,
          reason: 'the abandoned reconcile sends nothing more',
        );
      },
    );

    test(
      'a reconcile still queued when sign-out is asked for stands down '
      'instead of registering this device for the account that is signing '
      'out: it would find the pending invalidation sign-out has just '
      'recorded, settle it, and forget the ids sign-out still has to delete',
      () async {
        final server = _FakeServer();
        final account = _FakeAccount(server);
        final messaging = _FakeMessaging(server);
        final hold = messaging.holdCreateRequest[1] = Completer<void>();
        final service = _DeviceService(account, messaging);

        final inFlight = service.reconcile(campusId: '1');
        await pumpEventQueue();
        final queued = service.reconcile(campusId: '2'); // a campus change
        final signingOut = service.clearToken();

        expect(
          await inFlight,
          ReconcileOutcome.unavailable,
          reason: 'the reconcile in progress is abandoned by the sign-out',
        );
        expect(await queued, ReconcileOutcome.unavailable);
        await signingOut;
        hold.complete();
        await pumpEventQueue();

        expect(account.createTargetCalls, 1, reason: 'only the one in flight');
        expect(server.targets, isEmpty);
        expect(server.subscribers, isEmpty);
        expect(await store.readSubscriberIds(), isEmpty);
        expect(await store.readPendingTokenInvalidation(), isFalse);
      },
    );
  });

  group('bounds', () {
    testWidgets(
      'a run that hangs is abandoned at kNotificationRunTimeout and reports '
      'unavailable, and the runs queued behind it still execute: one request '
      'that never answered used to stall every later run until the app '
      'restarted',
      (tester) async {
        final server = _FakeServer();
        final messaging = _FakeMessaging(server);
        final hold = messaging.holdCreateRequest[1] = Completer<void>();
        final service = _DeviceService(_FakeAccount(server), messaging);

        ReconcileOutcome? hung;
        ReconcileOutcome? behind;
        unawaited(service.reconcile(campusId: '1').then((o) => hung = o));
        unawaited(service.reconcile(campusId: '1').then((o) => behind = o));

        await tester.pump(kNotificationRunTimeout - const Duration(seconds: 1));
        expect(hung, isNull, reason: 'still within its bound');
        expect(behind, isNull);

        await tester.pump(const Duration(seconds: 1));
        expect(hung, ReconcileOutcome.unavailable);
        await tester.pump();
        expect(behind, ReconcileOutcome.applied);

        hold.complete();
        await tester.pump();
      },
    );

    testWidgets(
      'an abandoned reconcile that answers late sends nothing more, and '
      'leaves the ids the run after it recorded as they were: a stale map '
      'written over them would drop ids that exist on the server - '
      'unrecoverably, since the client SDK cannot list subscribers',
      (tester) async {
        final server = _FakeServer();
        final messaging = _FakeMessaging(server);
        final hold = messaging.holdCreateRequest[1] = Completer<void>();
        final service = _DeviceService(_FakeAccount(server), messaging);

        ReconcileOutcome? behind;
        unawaited(service.reconcile(campusId: '1'));
        unawaited(service.reconcile(campusId: '1').then((o) => behind = o));
        await tester.pump(kNotificationRunTimeout);
        await tester.pump();
        expect(behind, ReconcileOutcome.applied);

        final recorded = await store.readSubscriberIds();
        expect(recorded.keys, {'general', 'news_oslo', 'news_national'});
        final requestsSoFar = messaging.createCalls;

        // The abandoned run's first subscribe finally answers.
        hold.complete();
        await tester.pump();

        expect(await store.readSubscriberIds(), recorded);
        expect(messaging.createCalls, requestsSoFar);
      },
    );

    testWidgets(
      'a reconcile abandoned at its bound has already recorded the '
      'subscribers it created before it hung: recorded only once the run '
      'finished, their ids were lost with it, and those subscribers could '
      'never be removed from this device',
      (tester) async {
        final server = _FakeServer();
        final messaging = _FakeMessaging(server);
        final hold = messaging.holdCreateRequest[2] = Completer<void>();
        final service = _DeviceService(_FakeAccount(server), messaging);

        ReconcileOutcome? outcome;
        unawaited(service.reconcile(campusId: '1').then((o) => outcome = o));
        await tester.pump(kNotificationRunTimeout);
        expect(outcome, ReconcileOutcome.unavailable);

        final created = server.subscribers.entries.single;
        expect(created.value.topicId, 'general');
        expect(await store.readSubscriberIds(), {'general': created.key});

        hold.complete();
        await tester.pump();
      },
    );

    testWidgets(
      'a sign-out cleanup abandoned at its bound does nothing when its '
      'requests answer late: by then the next student may have a target '
      'bound to a fresh token, which a late deleteToken() would kill, and '
      'ids a late clear would erase',
      (tester) async {
        final server = registeredDevice();
        final targetDeletion = Completer<void>();
        final account = _FakeAccount(server)
          ..holdDeleteTarget[1] = targetDeletion;
        final service = _DeviceService(account, _FakeMessaging(server));

        var cleanedUp = false;
        unawaited(service.clearToken().then((_) => cleanedUp = true));
        await tester.pump(kNotificationRunTimeout);
        expect(cleanedUp, isTrue);
        expect(await store.readPendingTokenInvalidation(), isTrue);

        // The next student signs in on this device.
        ReconcileOutcome? outcome;
        unawaited(service.reconcile(campusId: '2').then((o) => outcome = o));
        await tester.pump();
        expect(outcome, ReconcileOutcome.applied);
        expect(service.deleteTokenCalls, 1, reason: 'the pending retry');
        final recorded = await store.readSubscriberIds();
        expect(recorded, isNotEmpty);
        final tokenInUse = service.token;

        // The abandoned cleanup's target deletion finally answers.
        targetDeletion.complete();
        await tester.pump();

        expect(service.deleteTokenCalls, 1);
        expect(service.token, tokenInUse);
        expect(await store.readSubscriberIds(), recorded);
        expect(await store.readPendingTokenInvalidation(), isFalse);
      },
    );
  });

  group('answers that arrive after their run was abandoned', () {
    /// Starts a reconcile for campus 1 and pumps [elapse], returning its
    /// outcome if it has finished by then.
    Future<ReconcileOutcome?> reconcileFor(
      WidgetTester tester,
      NotificationService service, {
      Duration elapse = Duration.zero,
    }) async {
      ReconcileOutcome? outcome;
      unawaited(service.reconcile(campusId: '1').then((o) => outcome = o));
      await tester.pump(elapse);
      return outcome;
    }

    /// The server's subscribers on this device's stored target, by topic:
    /// exactly what the store must hold for every topic to be accounted for.
    Future<Map<String, String>> serverSubscribersOnStoredTarget(
      _FakeServer server,
    ) async {
      final targetId = await store.readTargetId();
      return <String, String>{
        for (final entry in server.subscribers.entries)
          if (entry.value.targetId == targetId) entry.value.topicId: entry.key,
      };
    }

    testWidgets(
      'an unsubscribe that lands after its run was abandoned still forgets '
      'that subscriber, so turning the topic back on subscribes this device '
      'again: its id used to stay stored, and reconcile then reported applied '
      'with nothing subscribed',
      (tester) async {
        final server = _FakeServer();
        final account = _FakeAccount(server);
        final messaging = _FakeMessaging(server);
        final service = _DeviceService(account, messaging);
        expect(await reconcileFor(tester, service), ReconcileOutcome.applied);
        final subscribed = await store.readSubscriberIds();

        // News off. Its first unsubscribe, news_oslo's, is carried out, but
        // the answer outlasts the run's bound.
        account.intent = {...account.intent, 'news': false};
        final lateAnswer = messaging.holdDeleteResponse[1] = Completer<void>();
        expect(
          await reconcileFor(tester, service, elapse: kNotificationRunTimeout),
          ReconcileOutcome.unavailable,
        );
        expect(server.subscribers, isNot(contains(subscribed['news_oslo'])));

        lateAnswer.complete();
        await tester.pump();
        expect(await store.readSubscriberIds(), isNot(contains('news_oslo')));

        // News back on.
        account.intent = {...account.intent, 'news': true};
        expect(await reconcileFor(tester, service), ReconcileOutcome.applied);
        expect(
          await store.readSubscriberIds(),
          await serverSubscribersOnStoredTarget(server),
        );
        expect(await store.readSubscriberIds(), contains('news_oslo'));
      },
    );

    testWidgets(
      'a subscribe that lands after its run was abandoned is still recorded '
      'while this device keeps its target and nothing holds the topic: '
      'dropped, the subscriber existed on the server with no id here, and '
      'this device could never unsubscribe from it',
      (tester) async {
        final server = _FakeServer();
        final account = _FakeAccount(server);
        final messaging = _FakeMessaging(server);
        // Create call 2 is news_oslo.
        final lateAnswer = messaging.holdCreateResponse[2] = Completer<void>();
        final service = _DeviceService(account, messaging);

        expect(
          await reconcileFor(tester, service, elapse: kNotificationRunTimeout),
          ReconcileOutcome.unavailable,
        );
        expect(await store.readSubscriberIds(), isNot(contains('news_oslo')));

        lateAnswer.complete();
        await tester.pump();
        expect((await store.readSubscriberIds()).keys, {'general', 'news_oslo'});
        expect(
          await store.readSubscriberIds(),
          await serverSubscribersOnStoredTarget(server),
        );

        // So turning news off does remove it.
        account.intent = {...account.intent, 'news': false};
        expect(await reconcileFor(tester, service), ReconcileOutcome.applied);
        expect(
          (await serverSubscribersOnStoredTarget(server)).keys,
          {'general'},
        );
      },
    );

    testWidgets(
      'a subscribe that answers after sign-out has cleared the store is not '
      'recorded: its subscriber belonged to a target this device no longer '
      'uses, and an id for it would tell the next student\'s reconcile that '
      'the topic was already held',
      (tester) async {
        final server = _FakeServer();
        final account = _FakeAccount(server);
        final messaging = _FakeMessaging(server);
        final lateAnswer = messaging.holdCreateResponse[2] = Completer<void>();
        final service = _DeviceService(account, messaging);
        await reconcileFor(tester, service, elapse: kNotificationRunTimeout);

        var signedOut = false;
        unawaited(service.clearToken().then((_) => signedOut = true));
        await tester.pump();
        expect(signedOut, isTrue);
        expect(server.targets, isEmpty);

        lateAnswer.complete();
        await tester.pump();
        expect(await store.readTargetId(), isNull);
        expect(await store.readSubscriberIds(), isEmpty);

        // The next student signs in, with news on too.
        expect(await reconcileFor(tester, service), ReconcileOutcome.applied);
        expect((await store.readSubscriberIds()).keys, {
          'general',
          'news_oslo',
          'news_national',
        });
        expect(
          await store.readSubscriberIds(),
          await serverSubscribersOnStoredTarget(server),
        );
      },
    );

    testWidgets(
      'a subscribe that answers after this device has moved to another push '
      'target is not recorded: its subscriber is attached to the old target, '
      'and an id for it would claim the topic is held on the new one',
      (tester) async {
        final server = _FakeServer();
        final account = _FakeAccount(server);
        final messaging = _FakeMessaging(server);
        final lateAnswer = messaging.holdCreateResponse[2] = Completer<void>();
        final service = _DeviceService(account, messaging);
        await reconcileFor(tester, service, elapse: kNotificationRunTimeout);
        final oldTarget = await store.readTargetId();

        // The target is deleted on the server, so the next run creates a new
        // one. News is off by then, so only the target stands in the late
        // answer's way.
        server.removeTarget(oldTarget!);
        account.intent = {...account.intent, 'news': false};
        expect(await reconcileFor(tester, service), ReconcileOutcome.applied);
        final newTarget = await store.readTargetId();
        expect(newTarget, isNot(oldTarget));

        lateAnswer.complete();
        await tester.pump();
        expect(await store.readTargetId(), newTarget);
        expect((await store.readSubscriberIds()).keys, {'general'});
        expect(
          await store.readSubscriberIds(),
          await serverSubscribersOnStoredTarget(server),
        );
      },
    );

    testWidgets(
      'a subscribe that answers late is not recorded over an entry recorded '
      'for its topic since: that entry is newer than the answer',
      (tester) async {
        final server = _FakeServer();
        final account = _FakeAccount(server);
        final messaging = _FakeMessaging(server);
        final lateAnswer = messaging.holdCreateResponse[2] = Completer<void>();
        final service = _DeviceService(account, messaging);
        await reconcileFor(tester, service, elapse: kNotificationRunTimeout);
        final lateSubscriber = (await serverSubscribersOnStoredTarget(
          server,
        ))['news_oslo'];

        // That subscriber is removed on the server - by an administrator,
        // say - and the next run subscribes this device afresh.
        server.subscribers.remove(lateSubscriber);
        expect(await reconcileFor(tester, service), ReconcileOutcome.applied);
        final recorded = await store.readSubscriberIds();
        expect(recorded['news_oslo'], allOf(isNotNull, isNot(lateSubscriber)));

        lateAnswer.complete();
        await tester.pump();
        expect(await store.readSubscriberIds(), recorded);
      },
    );

    testWidgets(
      'an unsubscribe that answers late forgets its topic only while the '
      'stored id is still the subscriber it deleted: an entry recorded since '
      'belongs to a live subscriber, and forgetting it would leave that '
      'subscriber with no id on this device',
      (tester) async {
        final server = _FakeServer();
        final account = _FakeAccount(server);
        final messaging = _FakeMessaging(server);
        final service = _DeviceService(account, messaging);
        await reconcileFor(tester, service);
        final oldTarget = await store.readTargetId();

        account.intent = {...account.intent, 'news': false};
        final lateAnswer = messaging.holdDeleteResponse[1] = Completer<void>();
        await reconcileFor(tester, service, elapse: kNotificationRunTimeout);

        // Before that answer arrives, news_oslo gets a new subscriber: the
        // target is deleted on the server, and with news back on the next
        // run subscribes this device afresh on a new one.
        server.removeTarget(oldTarget!);
        account.intent = {...account.intent, 'news': true};
        expect(await reconcileFor(tester, service), ReconcileOutcome.applied);
        final recorded = await store.readSubscriberIds();
        expect(recorded, contains('news_oslo'));
        expect(recorded, await serverSubscribersOnStoredTarget(server));

        lateAnswer.complete();
        await tester.pump();
        expect(await store.readSubscriberIds(), recorded);
      },
    );

    testWidgets(
      'a run records each change for its own topic alone, so a late answer '
      'recorded while that run is still going survives it: writing back its '
      'whole snapshot of the map would erase it',
      (tester) async {
        final server = _FakeServer();
        final account = _FakeAccount(server);
        final messaging = _FakeMessaging(server);
        final lateAnswer = messaging.holdCreateResponse[2] = Completer<void>();
        final service = _DeviceService(account, messaging);
        await reconcileFor(tester, service, elapse: kNotificationRunTimeout);

        // The student swaps news for events. The next run subscribes to
        // events_oslo (create call 3), then parks on events_national (4).
        account.intent = {...account.intent, 'news': false, 'events': true};
        final parked = messaging.holdCreateRequest[4] = Completer<void>();
        ReconcileOutcome? outcome;
        unawaited(service.reconcile(campusId: '1').then((o) => outcome = o));
        await tester.pump();
        expect((await store.readSubscriberIds()).keys, {
          'general',
          'events_oslo',
        });

        // The abandoned run's news_oslo answer lands in between.
        lateAnswer.complete();
        await tester.pump();
        expect((await store.readSubscriberIds()).keys, {
          'general',
          'events_oslo',
          'news_oslo',
        });

        parked.complete();
        await tester.pump();
        expect(outcome, ReconcileOutcome.applied);
        expect((await store.readSubscriberIds()).keys, {
          'general',
          'events_oslo',
          'news_oslo',
          'events_national',
        });
        expect(
          await store.readSubscriberIds(),
          await serverSubscribersOnStoredTarget(server),
        );
      },
    );
  });

  group('a sign-out whose session deletion fails', () {
    test(
      'leaves the student signed in, and their device registered and '
      'subscribed again: the cleanup has already detached it by then, and '
      'the launch reconciler brings it back only because logout() sets '
      'isLoading and clears it again',
      () async {
        final server = _FakeServer();
        final service = _DeviceService(
          _FakeAccount(server),
          _FakeMessaging(server),
        );
        final auth = _SessionKeepingAuthNotifier(service);
        final container = ProviderContainer(
          overrides: [
            notificationServiceProvider.overrideWithValue(service),
            authStateProvider.overrideWith((ref) => auth),
          ],
        );
        addTearDown(container.dispose);
        // Kept alive and rebuilt on every change, as BisoApp.build keeps it.
        container.listen(topicReconcileProvider, (previous, next) {});
        await pumpEventQueue(); // the auth notifier's own session check

        auth.signIn('student-a', campusId: '1');
        await pumpEventQueue();
        final firstTarget = await store.readTargetId();
        expect(server.targets.keys, [firstTarget]);

        await auth.logout();
        await pumpEventQueue();

        expect(container.read(authStateProvider).isAuthenticated, isTrue);
        final targetId = await store.readTargetId();
        expect(
          targetId,
          allOf(isNotNull, isNot(firstTarget)),
          reason: 'the cleanup deleted the first target',
        );
        expect(server.targets, {targetId: service.token});
        expect((await store.readSubscriberIds()).keys, {
          'general',
          'news_oslo',
          'news_national',
        });
        expect(
          await store.readSubscriberIds(),
          <String, String>{
            for (final entry in server.subscribers.entries)
              if (entry.value.targetId == targetId)
                entry.value.topicId: entry.key,
          },
        );
      },
    );
  });
}
