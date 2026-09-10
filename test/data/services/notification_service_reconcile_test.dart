import 'dart:async';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:biso/data/services/device_subscription_store.dart';
import 'package:biso/data/services/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAccount extends Account {
  _FakeAccount(this._prefs) : super(Client());

  Map<String, dynamic> _prefs;
  Map<String, dynamic> get saved => _prefs;

  /// How many times [updatePrefs] was called — used to assert that a read
  /// path does *not* write, without depending on the exact shape written.
  int updatePrefsCalls = 0;

  /// When true, [getPrefs] throws instead of returning [_prefs] - simulates a
  /// network/read failure distinct from "nothing stored yet", which is
  /// instead expressed by an empty (or absent-key) [_prefs].
  bool shouldFail = false;

  @override
  Future<models.Preferences> getPrefs() async {
    if (shouldFail) {
      throw AppwriteException('offline');
    }
    return models.Preferences(data: Map<String, dynamic>.from(_prefs));
  }

  @override
  Future<models.User> updatePrefs({required Map prefs}) async {
    updatePrefsCalls++;
    _prefs = Map<String, dynamic>.from(prefs);
    throw UnimplementedError('return value unused by the code under test');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
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

  group('loadTopicIntent', () {
    test('returns the defaults for an account that has never chosen', () async {
      final service = NotificationService.withAccount(
        _FakeAccount(<String, dynamic>{}),
      );
      expect(await service.loadTopicIntent(), {
        'news': true,
        'events': true,
        'jobs': true,
        'shop': true,
      });
    });

    test('reads a stored intent map', () async {
      final service = NotificationService.withAccount(
        _FakeAccount(<String, dynamic>{
          'notification_topics': <String, dynamic>{
            'news': false,
            'events': true,
            'jobs': false,
            'shop': false,
          },
        }),
      );
      expect((await service.loadTopicIntent())['news'], isFalse);
    });

    test(
      'migrates a legacy topic_subscriptions map, renaming products to shop '
      'and dropping expenses',
      () async {
        final service = NotificationService.withAccount(
          _FakeAccount(<String, dynamic>{
            'topic_subscriptions': <String, dynamic>{
              'products': false,
              'expenses': true,
              'events': false,
            },
          }),
        );
        final intent = await service.loadTopicIntent();
        expect(intent['shop'], isFalse);
        expect(intent['events'], isFalse);
        expect(intent.containsKey('expenses'), isFalse);
      },
    );

    test(
      'rethrows when the preferences read itself fails, instead of reporting '
      'it the same way as "nothing saved yet" - a caller must be able to '
      'tell the two apart, or a later toggle persists fabricated defaults '
      'over the student\'s real saved intent',
      () async {
        final account = _FakeAccount(<String, dynamic>{})..shouldFail = true;
        final service = NotificationService.withAccount(account);

        expect(
          () => service.loadTopicIntent(),
          throwsA(isA<AppwriteException>()),
        );
      },
    );
  });

  group('hasAnsweredTopicPrompt', () {
    test('is false for a brand new account', () async {
      final service = NotificationService.withAccount(
        _FakeAccount(<String, dynamic>{}),
      );
      expect(await service.hasAnsweredTopicPrompt(), isFalse);
    });

    test('is true once the marker is stored', () async {
      final service = NotificationService.withAccount(
        _FakeAccount(<String, dynamic>{
          'notification_topics_set_at': '2026-09-09T10:00:00.000Z',
        }),
      );
      expect(await service.hasAnsweredTopicPrompt(), isTrue);
    });

    test(
      'is false for a legacy account with only an old topic_subscriptions map '
      '- that map used to be written automatically on every launch, never '
      'because a student chose anything, so its presence cannot be told apart '
      'from someone who was never asked',
      () async {
        final service = NotificationService.withAccount(
          _FakeAccount(<String, dynamic>{
            'topic_subscriptions': <String, dynamic>{'events': false},
          }),
        );
        expect(await service.hasAnsweredTopicPrompt(), isFalse);
      },
    );

    test(
      'is false even when both the legacy map and subscriber ids are present '
      'but notification_topics_set_at is not, matching a real pre-migration '
      'account that has never seen the new prompt',
      () async {
        final service = NotificationService.withAccount(
          _FakeAccount(<String, dynamic>{
            'topic_subscriptions': <String, dynamic>{'events': false},
            'topic_subscriber_ids': <String, dynamic>{'events': 'sub-1'},
          }),
        );
        expect(await service.hasAnsweredTopicPrompt(), isFalse);
      },
    );
  });

  group('_loadTopicSubscriptions (via ensureTopicSubscriptionsLoaded)', () {
    test(
      'does not write prefs when topic_subscriptions is absent, so the '
      'legacy key stays read-only and cannot be mistaken for a real answer '
      'to the first-run prompt',
      () async {
        final account = _FakeAccount(<String, dynamic>{});
        final service = NotificationService.withAccount(account);

        final loaded = await service.ensureTopicSubscriptionsLoaded();

        expect(account.updatePrefsCalls, 0);
        expect(loaded, {
          'events': true,
          'products': true,
          'jobs': true,
          'expenses': false,
        });
      },
    );

    test(
      'still does not write prefs when a stored topic_subscriptions map is '
      'present, either - loading must never have a side effect on prefs',
      () async {
        final account = _FakeAccount(<String, dynamic>{
          'topic_subscriptions': <String, dynamic>{'events': false},
        });
        final service = NotificationService.withAccount(account);

        await service.ensureTopicSubscriptionsLoaded();

        expect(account.updatePrefsCalls, 0);
      },
    );
  });

  group('reconcile', () {
    Map<String, dynamic> intentPrefs({required bool events}) =>
        <String, dynamic>{
          'notification_topics': <String, dynamic>{
            'news': true,
            'events': events,
            'jobs': false,
            'shop': false,
          },
        };

    test(
      'serialises overlapping runs, so the stored subscriber map ends up '
      'holding every subscriber either run created: two runs that each read '
      'the stored map, diff, and write their own result back let the last '
      'write drop ids the other created - and since the client SDK cannot '
      'list subscribers, a dropped id is gone for good: the device can never '
      'unsubscribe from that topic, and every later create for it 409s',
      () async {
        final account = _FakeAccount(intentPrefs(events: false));
        final hold = Completer<void>();
        final messaging = _FakeMessaging()..holdFirstCreate = hold;
        final service = _ReconcilingService(account, messaging);

        // The launch reconciler starts first and parks on its first
        // subscribe.
        final launch = service.reconcile(campusId: '1');
        await pumpEventQueue();

        // Meanwhile the student turns Events on, and setTopic reconciles too.
        account.saved['notification_topics'] = <String, dynamic>{
          'news': true,
          'events': true,
          'jobs': false,
          'shop': false,
        };
        final toggle = service.reconcile(campusId: '1');
        await pumpEventQueue();

        hold.complete();
        final outcomes = await Future.wait([launch, toggle]);

        expect(
          await DeviceSubscriptionStore().readSubscriberIds(),
          messaging.subscribers,
          reason: 'every subscriber that exists server-side must still have '
              'its id stored on this device',
        );
        expect(messaging.subscribers.keys.toSet(), {
          'general',
          'news_oslo',
          'news_national',
          'events_oslo',
          'events_national',
        });
        expect(outcomes, [ReconcileOutcome.applied, ReconcileOutcome.applied]);
      },
    );

    test(
      'a run that throws still hands its own caller the error, and does not '
      'wedge the runs queued behind it',
      () async {
        final service = _ReconcilingService(
          _FakeAccount(intentPrefs(events: false)),
          _FakeMessaging(),
        )..targetThrowsOnce = StateError('storage unavailable');

        final failing = service.reconcile(campusId: '1');
        final queued = service.reconcile(campusId: '1');

        await expectLater(failing, throwsStateError);
        expect(await queued, ReconcileOutcome.applied);
      },
    );

    test(
      'reports unavailable, rather than throwing, when the FCM token cannot '
      'be fetched - e.g. SERVICE_NOT_AVAILABLE after the launch fetch had '
      'failed too, so no token was cached: a throw escapes into every '
      'caller, and requestPermission() used to report it as a denial',
      () async {
        final service = _ReconcilingService(
          _FakeAccount(intentPrefs(events: false)),
          _FakeMessaging(),
        )..tokenThrows = Exception('SERVICE_NOT_AVAILABLE');

        expect(
          await service.reconcile(campusId: '1'),
          ReconcileOutcome.unavailable,
        );
      },
    );

    test(
      'reports unavailable, not permissionDenied, when the permission check '
      'itself errors: a check that fails says nothing about the permission, '
      'and the permission dialog reads this outcome straight after a grant',
      () async {
        final service = _ReconcilingService(
          _FakeAccount(intentPrefs(events: false)),
          _FakeMessaging(),
        )..permissionThrows = PlatformException(code: 'unavailable');

        expect(
          await service.reconcile(campusId: '1'),
          ReconcileOutcome.unavailable,
        );
      },
    );

    test(
      'still reports permissionDenied when the check genuinely says '
      'permission is not granted',
      () async {
        final service = _ReconcilingService(
          _FakeAccount(intentPrefs(events: false)),
          _FakeMessaging(),
        )..permitted = false;

        expect(
          await service.reconcile(campusId: '1'),
          ReconcileOutcome.permissionDenied,
        );
      },
    );

    test(
      'areNotificationsEnabled() still reports false, rather than throwing, '
      'when the check errors - the chat settings tab and the chat list read '
      'that as "not enabled" and offer to request permission',
      () async {
        final service = _ReconcilingService(
          _FakeAccount(intentPrefs(events: false)),
          _FakeMessaging(),
        )..permissionThrows = PlatformException(code: 'unavailable');

        expect(await service.areNotificationsEnabled(), isFalse);
      },
    );
  });
}

models.Subscriber _subscriber({
  required String id,
  required String topicId,
  required String targetId,
}) => models.Subscriber(
  $id: id,
  $createdAt: '',
  $updatedAt: '',
  targetId: targetId,
  target: models.Target(
    $id: targetId,
    $createdAt: '',
    $updatedAt: '',
    name: 'device',
    userId: 'user-1',
    providerId: 'push',
    providerType: 'push',
    identifier: 'token-1',
    expired: false,
  ),
  userId: 'user-1',
  userName: 'Test',
  topicId: topicId,
  providerType: 'push',
);

/// Appwrite Messaging as the server sees one device: at most one subscriber
/// per topic, and a second create for a topic already held is rejected with a
/// 409, as Appwrite rejects it.
class _FakeMessaging extends Messaging {
  _FakeMessaging() : super(Client());

  /// topicId -> subscriber id, for every subscriber that exists server-side.
  final Map<String, String> subscribers = <String, String>{};

  /// When set, the first [createSubscriber] call waits for it before touching
  /// [subscribers], holding one run mid-flight while another starts.
  Completer<void>? holdFirstCreate;

  int _createCalls = 0;

  @override
  Future<models.Subscriber> createSubscriber({
    required String topicId,
    required String subscriberId,
    required String targetId,
  }) async {
    _createCalls++;
    final hold = holdFirstCreate;
    if (hold != null && _createCalls == 1) await hold.future;
    if (subscribers.containsKey(topicId)) {
      throw AppwriteException('subscriber already exists', 409);
    }
    subscribers[topicId] = subscriberId;
    return _subscriber(id: subscriberId, topicId: topicId, targetId: targetId);
  }

  @override
  Future deleteSubscriber({
    required String topicId,
    required String subscriberId,
  }) async {
    if (subscribers[topicId] != subscriberId) {
      throw AppwriteException('subscriber not found', 404);
    }
    subscribers.remove(topicId);
  }
}

/// Runs the real [NotificationService.reconcile] with each platform dependency
/// stood in for: the OS permission read, the FCM token, and the push target.
/// Messaging is [_FakeMessaging], and the subscriber map is the real
/// [DeviceSubscriptionStore] over mocked SharedPreferences.
class _ReconcilingService extends NotificationService {
  _ReconcilingService(super.account, Messaging messaging)
    : super.withAccount(messaging: messaging);

  /// What [checkPlatformPermission] reports, unless [permissionThrows] is set.
  bool permitted = true;
  Object? permissionThrows;

  /// Thrown from [fetchPlatformToken] instead of returning a token, when set.
  Object? tokenThrows;

  /// Thrown from the next [resolvePushTarget] call, then cleared - a failure
  /// `reconcile()` does not catch itself.
  Object? targetThrowsOnce;

  @override
  Future<bool> checkPlatformPermission() async {
    final failure = permissionThrows;
    if (failure != null) throw failure;
    return permitted;
  }

  @override
  Future<String?> fetchPlatformToken() async {
    final failure = tokenThrows;
    if (failure != null) throw failure;
    return 'token-1';
  }

  @override
  Future<String?> resolvePushTarget(
    String token, {
    bool Function()? isCurrent,
  }) async {
    final failure = targetThrowsOnce;
    if (failure != null) {
      targetThrowsOnce = null;
      throw failure;
    }
    return 'target-1';
  }
}
