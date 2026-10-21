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

  /// Sign-out deletes this device's push target; nothing to record here.
  @override
  Future deletePushTarget({required String targetId}) async {}
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

    test('migrates a legacy topic_subscriptions map, renaming products to shop '
        'and dropping expenses', () async {
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
    });

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
    test('does not write prefs when topic_subscriptions is absent, so the '
        'legacy key stays read-only and cannot be mistaken for a real answer '
        'to the first-run prompt', () async {
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
    });

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
        final launch = service.reconcile(campusId: '1', locale: 'en');
        await pumpEventQueue();

        // Meanwhile the student turns Events on, and setTopic reconciles too.
        account.saved['notification_topics'] = <String, dynamic>{
          'news': true,
          'events': true,
          'jobs': false,
          'shop': false,
        };
        final toggle = service.reconcile(campusId: '1', locale: 'en');
        await pumpEventQueue();

        hold.complete();
        final outcomes = await Future.wait([launch, toggle]);

        expect(
          await DeviceSubscriptionStore().readSubscriberIds(),
          messaging.subscribers,
          reason:
              'every subscriber that exists server-side must still have '
              'its id stored on this device',
        );
        expect(messaging.subscribers.keys.toSet(), {
          'general_en',
          'general_oslo_en',
          'news_oslo_en',
          'news_national_en',
          'events_oslo_en',
          'events_national_en',
        });
        expect(outcomes, [ReconcileOutcome.applied, ReconcileOutcome.applied]);
      },
    );

    test('a run that throws still hands its own caller the error, and does not '
        'wedge the runs queued behind it', () async {
      final service = _ReconcilingService(
        _FakeAccount(intentPrefs(events: false)),
        _FakeMessaging(),
      )..targetThrowsOnce = StateError('storage unavailable');

      final failing = service.reconcile(campusId: '1', locale: 'en');
      final queued = service.reconcile(campusId: '1', locale: 'en');

      await expectLater(failing, throwsStateError);
      expect(await queued, ReconcileOutcome.applied);
    });

    test('still subscribes this device to its language channels when the topic '
        'intent cannot be read, and deletes nothing: the general channels do '
        'not depend on any choice, and a run that stopped at the failed read '
        'left a student who had allowed notifications with no subscription at '
        'all', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'push_target_id': 'target-1',
        'topic_subscriber_ids': jsonEncode(<String, String>{
          'news_oslo_en': 'sub-news',
        }),
      });
      final account = _FakeAccount(intentPrefs(events: false))
        ..shouldFail = true;
      final messaging = _FakeMessaging()
        ..subscribers['news_oslo_en'] = 'sub-news';
      final service = _ReconcilingService(account, messaging);

      final outcome = await service.reconcile(campusId: '1', locale: 'en');

      expect(outcome, ReconcileOutcome.unavailable);
      expect(messaging.createCalls.toSet(), {'general_en', 'general_oslo_en'});
      expect(
        messaging.deleteCalls,
        isEmpty,
        reason: 'with no readable intent, no other subscription is touched',
      );
      expect(
        await DeviceSubscriptionStore().readSubscriberIds(),
        messaging.subscribers,
      );
      expect(messaging.subscribers.keys.toSet(), {
        'general_en',
        'general_oslo_en',
        'news_oslo_en',
      });
    });

    test(
      'with no readable intent, ensures the general channel in the requested '
      'language, and no campus channel for National',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'push_target_id': 'target-1',
        });
        final messaging = _FakeMessaging();
        final service = _ReconcilingService(
          _FakeAccount(intentPrefs(events: false))..shouldFail = true,
          messaging,
        );

        await service.reconcile(campusId: '5', locale: 'nb');

        expect(messaging.createCalls, ['general_no']);
      },
    );

    test('does nothing when the topic intent cannot be read and the general '
        'channels are already recorded on this device', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'push_target_id': 'target-1',
        'topic_subscriber_ids': jsonEncode(<String, String>{
          'general_en': 'sub-general',
          'general_oslo_en': 'sub-general-oslo',
        }),
      });
      final account = _FakeAccount(intentPrefs(events: false))
        ..shouldFail = true;
      final messaging = _FakeMessaging()
        ..subscribers['general_en'] = 'sub-general'
        ..subscribers['general_oslo_en'] = 'sub-general-oslo';
      final service = _ReconcilingService(account, messaging);

      expect(
        await service.reconcile(campusId: '1', locale: 'en'),
        ReconcileOutcome.unavailable,
      );
      expect(messaging.createCalls, isEmpty);
      expect(messaging.deleteCalls, isEmpty);
    });

    test('switching language moves every subscription to the other language in '
        'one run', () async {
      const enIds = [
        'general_en',
        'general_oslo_en',
        'events_oslo_en',
        'events_national_en',
      ];
      final noIds = enIds.map((id) => id.replaceAll('_en', '_no')).toList();
      SharedPreferences.setMockInitialValues(<String, Object>{
        'push_target_id': 'target-1',
        'topic_subscriber_ids': jsonEncode(<String, String>{
          for (final id in enIds) id: 'sub-$id',
        }),
      });
      final messaging = _FakeMessaging();
      for (final id in enIds) {
        messaging.subscribers[id] = 'sub-$id';
      }
      final service = _ReconcilingService(
        _FakeAccount(
          intentPrefs(events: true)..['notification_topics']['news'] = false,
        ),
        messaging,
      );

      final outcome = await service.reconcile(campusId: '1', locale: 'no');

      expect(outcome, ReconcileOutcome.applied);
      expect(messaging.createCalls.toSet(), noIds.toSet());
      expect(messaging.deleteCalls.toSet(), enIds.toSet());
      expect(messaging.subscribers.keys.toSet(), noIds.toSet());
      expect(
        (await DeviceSubscriptionStore().readSubscriberIds()).keys.toSet(),
        noIds.toSet(),
      );
    });

    test('switching language deletes before it creates, and does not subscribe '
        'to the new language of a channel whose old subscription could not be '
        'deleted: the phone may miss that channel until the next run, but is '
        'never on both languages of it at once', () async {
      const enIds = [
        'general_en',
        'general_oslo_en',
        'events_oslo_en',
        'events_national_en',
      ];
      SharedPreferences.setMockInitialValues(<String, Object>{
        'push_target_id': 'target-1',
        'topic_subscriber_ids': jsonEncode(<String, String>{
          for (final id in enIds) id: 'sub-$id',
        }),
      });
      final messaging = _FakeMessaging()..failDeletes.add('events_oslo_en');
      for (final id in enIds) {
        messaging.subscribers[id] = 'sub-$id';
      }
      final service = _ReconcilingService(
        _FakeAccount(
          intentPrefs(events: true)..['notification_topics']['news'] = false,
        ),
        messaging,
      );

      final outcome = await service.reconcile(campusId: '1', locale: 'no');

      expect(outcome, ReconcileOutcome.partiallyFailed);
      final firstCreate = messaging.calls.indexWhere(
        (c) => c.startsWith('create '),
      );
      final lastDelete = messaging.calls.lastIndexWhere(
        (c) => c.startsWith('delete '),
      );
      expect(
        lastDelete,
        lessThan(firstCreate),
        reason: 'every delete is attempted before the first create',
      );
      expect(messaging.deleteCalls.toSet(), enIds.toSet());
      expect(messaging.createCalls.toSet(), {
        'general_no',
        'general_oslo_no',
        'events_national_no',
      });
      expect(messaging.subscribers.keys.toSet(), {
        'events_oslo_en',
        'general_no',
        'general_oslo_no',
        'events_national_no',
      });
      expect(
        await DeviceSubscriptionStore().readSubscriberIds(),
        messaging.subscribers,
      );

      // The next run, with the delete going through, finishes the move.
      messaging.failDeletes.clear();
      expect(
        await service.reconcile(campusId: '1', locale: 'no'),
        ReconcileOutcome.applied,
      );
      expect(messaging.subscribers.keys.toSet(), {
        'general_no',
        'general_oslo_no',
        'events_oslo_no',
        'events_national_no',
      });
    });

    test('with no readable intent during a language switch, deletes the other '
        'language and the general channels of another campus, ensures the '
        'general channels in the new language, and leaves the student\'s own '
        'topics in the new language alone', () async {
      const held = <String, String>{
        'general_en': 'sub-general-en',
        'general_oslo_en': 'sub-general-oslo-en',
        'news_oslo_en': 'sub-news-oslo-en',
        'general_bergen_no': 'sub-general-bergen-no',
        'events_oslo_no': 'sub-events-oslo-no',
      };
      SharedPreferences.setMockInitialValues(<String, Object>{
        'push_target_id': 'target-1',
        'topic_subscriber_ids': jsonEncode(held),
      });
      final messaging = _FakeMessaging()..subscribers.addAll(held);
      final service = _ReconcilingService(
        _FakeAccount(intentPrefs(events: false))..shouldFail = true,
        messaging,
      );

      final outcome = await service.reconcile(campusId: '1', locale: 'no');

      expect(outcome, ReconcileOutcome.unavailable);
      expect(messaging.deleteCalls.toSet(), {
        'general_en',
        'general_oslo_en',
        'news_oslo_en',
        'general_bergen_no',
      });
      expect(messaging.createCalls.toSet(), {'general_no', 'general_oslo_no'});
      expect(
        messaging.calls.lastIndexWhere((c) => c.startsWith('delete ')),
        lessThan(messaging.calls.indexWhere((c) => c.startsWith('create '))),
        reason: 'deletes run before creates here too',
      );
      expect(messaging.subscribers.keys.toSet(), {
        'general_no',
        'general_oslo_no',
        'events_oslo_no',
      });
      expect(
        await DeviceSubscriptionStore().readSubscriberIds(),
        messaging.subscribers,
      );
    });

    test(
      'reconcile maps a Bokmål language code to the Norwegian channels',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'push_target_id': 'target-1',
        });
        final messaging = _FakeMessaging();
        final service = _ReconcilingService(
          _FakeAccount(intentPrefs(events: false)),
          messaging,
        );

        await service.reconcile(campusId: '2', locale: 'nb');

        expect(messaging.subscribers.keys, isNotEmpty);
        expect(
          messaging.subscribers.keys.every((id) => id.endsWith('_no')),
          isTrue,
        );
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
          await service.reconcile(campusId: '1', locale: 'en'),
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
          await service.reconcile(campusId: '1', locale: 'en'),
          ReconcileOutcome.unavailable,
        );
      },
    );

    test('still reports permissionDenied when the check genuinely says '
        'permission is not granted', () async {
      final service = _ReconcilingService(
        _FakeAccount(intentPrefs(events: false)),
        _FakeMessaging(),
      )..permitted = false;

      expect(
        await service.reconcile(campusId: '1', locale: 'en'),
        ReconcileOutcome.permissionDenied,
      );
    });

    test('areNotificationsEnabled() still reports false, rather than throwing, '
        'when the check errors - the chat settings tab and the chat list read '
        'that as "not enabled" and offer to request permission', () async {
      final service = _ReconcilingService(
        _FakeAccount(intentPrefs(events: false)),
        _FakeMessaging(),
      )..permissionThrows = PlatformException(code: 'unavailable');

      expect(await service.areNotificationsEnabled(), isFalse);
    });
  });

  group('initialize', () {
    Map<String, dynamic> intentPrefs() => <String, dynamic>{
      'notification_topics': <String, dynamic>{
        'news': true,
        'events': false,
        'jobs': false,
        'shop': false,
      },
    };

    test('listens for token refreshes even when the first token fetch fails, '
        'and a refresh then subscribes this device: on iOS the first fetch '
        'commonly fails before APNs has answered, and the listener was only '
        'registered after a successful one, so nothing ever heard the token '
        'Firebase issued afterwards', () async {
      final messaging = _FakeMessaging();
      final service = _ReconcilingService(
        _FakeAccount(intentPrefs()),
        messaging,
      )..tokenThrows = Exception('APNS token has not been set yet');

      await service.initialize();
      expect(service.fcmToken, isNull);

      // The launch reconciler runs for the student's campus, and has no
      // token to register yet.
      expect(
        await service.reconcile(campusId: '1', locale: 'en'),
        ReconcileOutcome.unavailable,
      );

      service.tokenRefreshes.add('token-2');
      await pumpEventQueue();

      expect(service.fcmToken, 'token-2');
      expect(messaging.subscribers.keys.toSet(), {
        'general_en',
        'general_oslo_en',
        'news_oslo_en',
        'news_national_en',
      });
    });

    test(
      'listens only once, however many times it is called before it has '
      'succeeded: a second listener would reconcile twice for every refresh',
      () async {
        final messaging = _FakeMessaging();
        final service =
            _ReconcilingService(_FakeAccount(intentPrefs()), messaging)
              ..configureThrowsOnce = Exception('not configured yet')
              ..tokenThrows = Exception('APNS token has not been set yet');

        await service.initialize(); // fails, so it is not yet initialized
        await service.initialize();
        await service.reconcile(campusId: '1', locale: 'en'); // no token yet
        expect(service.permissionChecks, 1);

        service.tokenRefreshes.add('token-2');
        await pumpEventQueue();

        expect(service.permissionChecks, 2, reason: 'one more reconcile run');
        expect(messaging.createCalls, [
          'general_en',
          'general_oslo_en',
          'news_oslo_en',
          'news_national_en',
        ]);
      },
    );

    test(
      'a refresh before anything has reconciled changes no subscription, and '
      'leaves its token for the first reconcile: with no campus known yet it '
      'reconciled for national, deleting every campus topic the launch '
      'reconcile then had to create again',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'push_target_id': 'target-1',
          'topic_subscriber_ids': jsonEncode(<String, String>{
            'news_oslo_en': 'sub-news',
          }),
        });
        final messaging = _FakeMessaging()
          ..subscribers['news_oslo_en'] = 'sub-news';
        final service = _ReconcilingService(
          _FakeAccount(intentPrefs()),
          messaging,
        )..tokenThrows = Exception('APNS token has not been set yet');

        await service.initialize();
        service.tokenRefreshes.add('token-2');
        await pumpEventQueue();

        expect(service.fcmToken, 'token-2');
        expect(service.permissionChecks, 0, reason: 'no reconcile ran');
        expect(messaging.createCalls, isEmpty);
        expect(messaging.deleteCalls, isEmpty);

        // The launch reconcile, for the student's campus, uses that token.
        expect(
          await service.reconcile(campusId: '1', locale: 'en'),
          ReconcileOutcome.applied,
        );
        expect(messaging.createCalls, [
          'general_en',
          'general_oslo_en',
          'news_national_en',
        ]);
        expect(messaging.deleteCalls, isEmpty);
      },
    );

    test('a refresh after sign-out does not reconcile: the campus belonged to '
        'the student who signed out', () async {
      final messaging = _FakeMessaging();
      final service = _ReconcilingService(
        _FakeAccount(intentPrefs()),
        messaging,
      )..tokenThrows = Exception('APNS token has not been set yet');

      await service.initialize();
      await service.reconcile(campusId: '1', locale: 'en'); // no token yet
      await service.clearToken();
      final checksBefore = service.permissionChecks;

      service.tokenRefreshes.add('token-3');
      await pumpEventQueue();

      expect(service.permissionChecks, checksBefore);
      expect(messaging.createCalls, isEmpty);
    });
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

  /// Every topic [createSubscriber] and [deleteSubscriber] were called for,
  /// in call order.
  final List<String> createCalls = <String>[];
  final List<String> deleteCalls = <String>[];

  /// Both kinds of call in one list, in call order, as `create <topic>` and
  /// `delete <topic>`.
  final List<String> calls = <String>[];

  /// Topics whose [deleteSubscriber] fails with a server error.
  final Set<String> failDeletes = <String>{};

  int _createCalls = 0;

  @override
  Future<models.Subscriber> createSubscriber({
    required String topicId,
    required String subscriberId,
    required String targetId,
  }) async {
    _createCalls++;
    createCalls.add(topicId);
    calls.add('create $topicId');
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
    deleteCalls.add(topicId);
    calls.add('delete $topicId');
    if (failDeletes.contains(topicId)) {
      throw AppwriteException('server error', 500);
    }
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

  /// How many times [checkPlatformPermission] was called: once per reconcile
  /// run that gets that far.
  int permissionChecks = 0;

  /// Thrown from [fetchPlatformToken] instead of returning a token, when set.
  Object? tokenThrows;

  /// Thrown from the next [resolvePushTarget] call, then cleared - a failure
  /// `reconcile()` does not catch itself.
  Object? targetThrowsOnce;

  /// Thrown from the next [configurePlatformMessaging] call, then cleared.
  Object? configureThrowsOnce;

  /// Stands in for Firebase's `onTokenRefresh`.
  final StreamController<String> tokenRefreshes =
      StreamController<String>.broadcast();

  @override
  Future<void> configurePlatformMessaging() async {
    final failure = configureThrowsOnce;
    configureThrowsOnce = null;
    if (failure != null) throw failure;
  }

  @override
  Stream<String> get platformTokenRefreshes => tokenRefreshes.stream;

  /// Sign-out's token invalidation, which succeeds.
  @override
  Future<void> deletePlatformToken() async {}

  /// The push target every run resolves, recorded in the store as the real
  /// [resolvePushTarget] records it: subscriber ids are only ever recorded
  /// against the stored target.
  static const String _targetId = 'target-1';

  @override
  Future<bool> checkPlatformPermission() async {
    permissionChecks++;
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
    await DeviceSubscriptionStore().writeTargetId(_targetId);
    return _targetId;
  }
}
