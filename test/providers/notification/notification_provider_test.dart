import 'dart:async';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:biso/data/services/notification_service.dart';
import 'package:biso/providers/notification/notification_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The [Account] backing [_FakeNotificationService].
///
/// Only used for the constructor's initial `loadTopicIntent()` read (via
/// `TopicIntentNotifier._load()`) - every method `setTopic` itself calls
/// (`saveTopicIntent`, `reconcile`) is overridden below and never reaches
/// this account, so it only ever needs to support a read.
class _FakeAccount extends Account {
  _FakeAccount(this._prefs) : super(Client());

  final Map<String, dynamic> _prefs;

  @override
  Future<models.Preferences> getPrefs() async =>
      models.Preferences(data: Map<String, dynamic>.from(_prefs));
}

/// A [NotificationService] whose [saveTopicIntent] and [reconcile] are
/// controlled directly by the test, so [TopicIntentNotifier] can be exercised
/// without a network, Firebase, or Appwrite Messaging - none of which have
/// any test-double support in this project (no mockito/mocktail either; see
/// the hand-written fakes throughout `test/data/services/`).
class _FakeNotificationService extends NotificationService {
  _FakeNotificationService(Map<String, dynamic> seededPrefs)
    : super.withAccount(_FakeAccount(seededPrefs));

  /// Thrown from [saveTopicIntent], when set. Applies to every call unless
  /// [saveThrowsOnCall] restricts it to one specific call number (1-indexed,
  /// counted by [saveCalls]).
  Object? saveThrows;
  int? saveThrowsOnCall;
  int saveCalls = 0;
  Map<String, bool>? lastSaved;

  /// Every map ever passed to [saveTopicIntent], in call order — including
  /// ones that then threw, which never reach [lastSaved].
  final List<Map<String, bool>> savedIntents = [];

  /// When set, the Nth call to [saveTopicIntent] (1-indexed, matching
  /// [saveCalls] after increment) waits for `saveGates[n - 1]` before
  /// proceeding. Lets a test control exactly when each call's "network
  /// response" arrives, independent of the order the calls were made in -
  /// see the finding-3 race test below.
  List<Completer<void>>? saveGates;

  @override
  Future<void> saveTopicIntent(Map<String, bool> intent) async {
    saveCalls++;
    final gates = saveGates;
    if (gates != null && saveCalls <= gates.length) {
      await gates[saveCalls - 1].future;
    }
    final failure = saveThrows;
    if (failure != null &&
        (saveThrowsOnCall == null || saveThrowsOnCall == saveCalls)) {
      throw failure;
    }
    lastSaved = Map<String, bool>.from(intent);
    savedIntents.add(Map<String, bool>.from(intent));
  }

  /// Returned from the next [reconcile] call - defaults to the common case.
  ReconcileOutcome reconcileResult = ReconcileOutcome.applied;

  /// Thrown from the next [reconcile] call instead of returning
  /// [reconcileResult], when set.
  Object? reconcileThrows;

  int reconcileCalls = 0;
  String? lastReconcileCampusId;

  @override
  Future<ReconcileOutcome> reconcile({required String? campusId}) async {
    reconcileCalls++;
    lastReconcileCampusId = campusId;
    final failure = reconcileThrows;
    if (failure != null) throw failure;
    return reconcileResult;
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

  const seededIntent = <String, dynamic>{
    'notification_topics': <String, dynamic>{
      'news': true,
      'events': true,
      'jobs': true,
      'shop': true,
    },
  };

  /// Builds a notifier and waits for its constructor-triggered seed load to
  /// resolve, so `state.value` is populated before a test drives it.
  Future<TopicIntentNotifier> buildNotifier(
    _FakeNotificationService service, {
    String? campusId = '1',
  }) async {
    final notifier = TopicIntentNotifier(service, campusId);
    await pumpEventQueue();
    return notifier;
  }

  group('TopicIntentNotifier.setTopic', () {
    test(
      'returns null and reverts the switch when the save fails, without '
      'attempting to reconcile a choice that was never actually recorded',
      () async {
        final service = _FakeNotificationService(seededIntent)
          ..saveThrows = Exception('offline');
        final notifier = await buildNotifier(service);

        final result = await notifier.setTopic('events', false);

        expect(result, isNull);
        expect(
          notifier.state.value?['events'],
          isTrue,
          reason: 'reverted to the value from before the toggle',
        );
        expect(
          service.reconcileCalls,
          0,
          reason: 'a failed save must never be followed by a reconcile',
        );
      },
    );

    test(
      "propagates a successful reconcile's outcome and keeps the new value",
      () async {
        final service = _FakeNotificationService(seededIntent)
          ..reconcileResult = ReconcileOutcome.applied;
        final notifier = await buildNotifier(service);

        final result = await notifier.setTopic('events', false);

        expect(result, ReconcileOutcome.applied);
        expect(notifier.state.value?['events'], isFalse);
      },
    );

    test("propagates a failed or partial reconcile's outcome too, and still "
        'does not revert the switch - the intent is genuinely saved even '
        'though this device could not be fully updated', () async {
      final service = _FakeNotificationService(seededIntent)
        ..reconcileResult = ReconcileOutcome.partiallyFailed;
      final notifier = await buildNotifier(service);

      final result = await notifier.setTopic('events', false);

      expect(result, ReconcileOutcome.partiallyFailed);
      expect(
        notifier.state.value?['events'],
        isFalse,
        reason: 'save succeeded, so the switch must stay as the student set it',
      );
    });

    test('still does not revert when reconcile throws unexpectedly, reporting '
        'unavailable instead of letting the exception be mistaken for a '
        'failed save', () async {
      final service = _FakeNotificationService(seededIntent)
        ..reconcileThrows = Exception('boom');
      final notifier = await buildNotifier(service);

      final result = await notifier.setTopic('events', false);

      expect(result, ReconcileOutcome.unavailable);
      expect(notifier.state.value?['events'], isFalse);
    });

    test("passes the notifier's campus id through to reconcile", () async {
      final service = _FakeNotificationService(seededIntent);
      final notifier = await buildNotifier(service, campusId: '2');

      await notifier.setTopic('news', false);

      expect(service.lastReconcileCampusId, '2');
    });

    test('returns null without saving or reconciling when called before the '
        'initial load has produced a value to update', () async {
      final service = _FakeNotificationService(seededIntent);
      // Deliberately not awaited: the constructor's seed load is still
      // pending, so `state.value` is null at this point. Nothing yields
      // back to the event loop between construction and the assertions
      // below, so the pending load cannot race ahead of them.
      final notifier = TopicIntentNotifier(service, '1');

      final result = await notifier.setTopic('events', false);

      expect(result, isNull);
      expect(service.saveCalls, 0);
      expect(service.reconcileCalls, 0);
    });

    test(
      'serialises overlapping calls so the server ends up holding both '
      'changes, instead of whichever save "arrives" last winning with a '
      'stale snapshot (finding 3): without serialising the actual save '
      'calls, releasing the second call\'s save before the first\'s lets '
      'the older payload land last and resurrect "events: true"',
      () async {
        final gates = [Completer<void>(), Completer<void>()];
        final service = _FakeNotificationService(seededIntent)
          ..saveGates = gates;
        final notifier = await buildNotifier(service);

        final futureA = notifier.setTopic('news', false);
        final futureB = notifier.setTopic('events', false);

        // Resolve out of call order: the *second* call's "network response"
        // arrives first. Serialised saves never let the second call's save
        // start until the first one has finished, so this ordering cannot
        // matter to them; unserialised saves fire both at once, and this is
        // exactly the ordering that lets the first call's stale payload land
        // last and win.
        gates[1].complete();
        await pumpEventQueue();
        gates[0].complete();

        final results = await Future.wait([futureA, futureB]);

        expect(results, [ReconcileOutcome.applied, ReconcileOutcome.applied]);
        expect(
          service.lastSaved,
          {'news': false, 'events': false, 'jobs': true, 'shop': true},
          reason: 'the last write to actually reach the server must contain '
              'both changes',
        );
        expect(
          notifier.state.value,
          {'news': false, 'events': false, 'jobs': true, 'shop': true},
        );
      },
    );

    test(
      'a queued save reads the merge base fresh at execution time, so a '
      'later call does not resurrect an earlier call\'s change after that '
      'change failed and was reverted (finding 3): capturing the merge base '
      'when each call was made, instead of when its save actually runs, '
      'would still carry the failed "news" change into the "events" save '
      'that runs after it',
      () async {
        final service = _FakeNotificationService(seededIntent)
          ..saveThrows = Exception('offline')
          ..saveThrowsOnCall = 1;
        final notifier = await buildNotifier(service);

        final futureA = notifier.setTopic('news', false);
        final futureB = notifier.setTopic('events', false);
        final results = await Future.wait([futureA, futureB]);

        expect(results[0], isNull, reason: "news's save failed");
        expect(
          results[1],
          ReconcileOutcome.applied,
          reason: "events's save succeeded",
        );
        expect(
          service.saveCalls,
          2,
          reason: 'both calls must still attempt to save exactly once',
        );
        expect(
          service.lastSaved,
          {'news': true, 'events': false, 'jobs': true, 'shop': true},
          reason: '"news" must be back to true - its own save failed - and '
              'must not be dragged along by the events save that ran after '
              'it',
        );
        expect(
          notifier.state.value,
          {'news': true, 'events': false, 'jobs': true, 'shop': true},
          reason: 'the switches must show exactly what the server has',
        );
      },
    );

    test(
      "a successful save must not clobber a *different* topic's concurrent "
      'optimistic flip with the stale snapshot it captured before that flip '
      'happened (finding 3): writing the merge base computed at the top of '
      "this call back to state on success, instead of re-merging against "
      "state as it stands right now, would revert 'events' the instant "
      "'news' finishes saving, even though 'events' has not failed - it "
      "has not even been attempted yet",
      () async {
        final gates = [Completer<void>(), Completer<void>()];
        final service = _FakeNotificationService(seededIntent)
          ..saveGates = gates;
        final notifier = await buildNotifier(service);

        final futureA = notifier.setTopic('news', false);
        // Let commit A start and reach its save call: it captures its merge
        // base here, strictly before 'events' is touched below.
        await pumpEventQueue();
        expect(service.saveCalls, 1);

        final futureB = notifier.setTopic('events', false);
        expect(
          notifier.state.value?['events'],
          isFalse,
          reason: 'the optimistic flip must be visible immediately',
        );

        // Let A's save resolve and its own commit run to completion,
        // reconcile included - but not commit B's, which is still parked on
        // gates[1]. A stale write-back would revert 'events' to true right
        // here, on A's success, despite 'events' playing no part in it.
        gates[0].complete();
        await pumpEventQueue();
        expect(
          service.saveCalls,
          2,
          reason: "commit B's save has started and is now parked on gates[1]",
        );
        expect(
          notifier.state.value?['events'],
          isFalse,
          reason: "A's own success must not revert a switch it does not own",
        );

        gates[1].complete();
        final results = await Future.wait([futureA, futureB]);

        expect(results, [ReconcileOutcome.applied, ReconcileOutcome.applied]);
        expect(
          service.lastSaved,
          {'news': false, 'events': false, 'jobs': true, 'shop': true},
        );
        expect(
          notifier.state.value,
          {'news': false, 'events': false, 'jobs': true, 'shop': true},
        );
      },
    );
  });
}
