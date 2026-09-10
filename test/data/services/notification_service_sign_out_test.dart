import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:biso/data/services/device_subscription_store.dart';
import 'package:biso/data/services/notification_service.dart';
import 'package:flutter/services.dart';
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

  /// When set, [deletePushTarget] throws it instead of deleting.
  AppwriteException? deleteTargetThrows;

  /// When set, [deletePushTarget] waits for it before doing anything.
  Completer<void>? holdDeleteTarget;

  int deleteTargetCalls = 0;
  int updateTargetCalls = 0;
  int createTargetCalls = 0;

  @override
  Future deletePushTarget({required String targetId}) async {
    deleteTargetCalls++;
    final hold = holdDeleteTarget;
    if (hold != null) await hold.future;
    final failure = deleteTargetThrows;
    if (failure != null) throw failure;
    if (server.targets.remove(targetId) == null) {
      throw AppwriteException('target not found', 404);
    }
    // Deleting a target kills every subscriber attached to it.
    server.subscribers.removeWhere((_, s) => s.targetId == targetId);
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
      'notification_topics': <String, dynamic>{
        'news': true,
        'events': false,
        'jobs': false,
        'shop': false,
      },
    },
  );
}

class _FakeMessaging extends Messaging {
  _FakeMessaging(this.server) : super(Client());

  final _FakeServer server;

  /// When set, create call number [holdCreateCall] (counting from 1) waits
  /// for it before touching the server, holding its run mid-flight.
  Completer<void>? holdCreate;
  int holdCreateCall = 1;

  /// When set, [deleteSubscriber] throws it instead of deleting.
  AppwriteException? deleteThrows;

  int createCalls = 0;

  @override
  Future<models.Subscriber> createSubscriber({
    required String topicId,
    required String subscriberId,
    required String targetId,
  }) async {
    final call = ++createCalls;
    final hold = holdCreate;
    if (hold != null && call == holdCreateCall) await hold.future;
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
    return _subscriber(id: id, topicId: topicId, targetId: targetId);
  }

  @override
  Future deleteSubscriber({
    required String topicId,
    required String subscriberId,
  }) async {
    final failure = deleteThrows;
    if (failure != null) throw failure;
    if (server.subscribers[subscriberId]?.topicId != topicId) {
      throw AppwriteException('subscriber not found', 404);
    }
    server.subscribers.remove(subscriberId);
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
  Future<void> writeSubscriberIds(Map<String, String> ids) async => _fail();

  @override
  Future<bool> readPendingTokenInvalidation() async => _fail();

  @override
  Future<void> writePendingTokenInvalidation() async => _fail();

  @override
  Future<void> clear() async => _fail();
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
      '- before anyone signs in',
      () async {
        final server = registeredDevice();
        await (_DeviceService(
          _FakeAccount(server)
            ..deleteTargetThrows = AppwriteException('offline', 0),
          _FakeMessaging(server),
        )..deleteTokenThrows = Exception('SERVICE_NOT_AVAILABLE')).clearToken();
        expect(await store.readPendingTokenInvalidation(), isTrue);

        final account = _FakeAccount(server);
        final restarted = _DeviceService(account, _FakeMessaging(server));
        await restarted.retryPendingTokenInvalidation();

        expect(restarted.deleteTokenCalls, 1);
        expect(await store.readPendingTokenInvalidation(), isFalse);
        expect(await store.readSubscriberIds(), isEmpty);
        expect(await store.readTargetId(), isNull);
        expect(account.updateTargetCalls + account.createTargetCalls, 0);
      },
    );
  });

  group('the queue', () {
    test(
      'clearToken() waits behind a reconcile in flight instead of '
      'interleaving with it: run alongside, it cleared the store while the '
      'reconcile was still subscribing, and the reconcile then wrote its ids '
      'back - leaving a signed-out account\'s ids on the device, and its '
      'target and subscribers on the server',
      () async {
        final server = _FakeServer();
        final account = _FakeAccount(server);
        final messaging = _FakeMessaging(server)
          ..holdCreate = Completer<void>();
        final service = _DeviceService(account, messaging);

        final reconciling = service.reconcile(campusId: '1');
        await pumpEventQueue(); // parked on its first subscribe
        expect(server.targets, hasLength(1));

        final signingOut = service.clearToken();
        await pumpEventQueue();
        expect(
          account.deleteTargetCalls,
          0,
          reason: 'sign-out must wait for the reconcile in flight',
        );

        messaging.holdCreate!.complete();
        await Future.wait([reconciling, signingOut]);

        expect(server.targets, isEmpty);
        expect(server.subscribers, isEmpty);
        expect(await store.readSubscriberIds(), isEmpty);
        expect(await store.readTargetId(), isNull);
        expect(await store.readPendingTokenInvalidation(), isFalse);
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
        final messaging = _FakeMessaging(server)
          ..holdCreate = Completer<void>();
        final service = _DeviceService(account, messaging);

        final inFlight = service.reconcile(campusId: '1');
        await pumpEventQueue();
        final queued = service.reconcile(campusId: '2'); // a campus change
        final signingOut = service.clearToken();

        messaging.holdCreate!.complete();
        expect(await inFlight, ReconcileOutcome.applied);
        expect(await queued, ReconcileOutcome.unavailable);
        await signingOut;

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
        final messaging = _FakeMessaging(server)
          ..holdCreate = Completer<void>();
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

        messaging.holdCreate!.complete();
        await tester.pump();
      },
    );

    testWidgets(
      'an abandoned reconcile that answers late writes nothing and sends '
      'nothing more: the run after it has recorded its own ids, and the late '
      'run\'s stale map written over them would drop ids that exist on the '
      'server - unrecoverably, since the client SDK cannot list subscribers',
      (tester) async {
        final server = _FakeServer();
        final messaging = _FakeMessaging(server)
          ..holdCreate = Completer<void>();
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
        messaging.holdCreate!.complete();
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
        final messaging = _FakeMessaging(server)
          ..holdCreate = Completer<void>()
          ..holdCreateCall = 2;
        final service = _DeviceService(_FakeAccount(server), messaging);

        ReconcileOutcome? outcome;
        unawaited(service.reconcile(campusId: '1').then((o) => outcome = o));
        await tester.pump(kNotificationRunTimeout);
        expect(outcome, ReconcileOutcome.unavailable);

        final created = server.subscribers.entries.single;
        expect(created.value.topicId, 'general');
        expect(await store.readSubscriberIds(), {'general': created.key});

        messaging.holdCreate!.complete();
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
        final account = _FakeAccount(server)..holdDeleteTarget = targetDeletion;
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
}
