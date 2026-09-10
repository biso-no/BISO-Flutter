import 'dart:async';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/auth_service.dart';
import 'package:biso/data/services/notification_service.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/notification/notification_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const String _studentA = 'student-a';
const String _studentB = 'student-b';

models.User _user(String id) => models.User(
  $id: id,
  $createdAt: '',
  $updatedAt: '',
  name: id,
  registration: '',
  status: true,
  labels: const <String>[],
  passwordUpdate: '',
  email: '$id@bi.no',
  phone: '',
  emailVerification: true,
  phoneVerification: false,
  mfa: false,
  prefs: models.Preferences(data: <String, dynamic>{}),
  targets: const <models.Target>[],
  accessedAt: '',
);

/// The [Account] backing [_FakeNotificationService] - the server, as far as
/// these tests are concerned.
///
/// [prefsByStudent] is what the server holds for each account, and [session]
/// is whose account this device is signed in to: every read and every write
/// goes to that account, as it would through Appwrite. A save lands only
/// through the real `saveTopicIntent()`, and is read back through the real
/// `loadTopicIntent()` - by `TopicIntentNotifier._load()`, and by a test
/// asking what the server has.
class _FakeAccount extends Account {
  _FakeAccount(Map<String, dynamic> prefs)
    : prefsByStudent = <String, Map<String, dynamic>>{
        _studentA: Map<String, dynamic>.from(prefs),
        _studentB: <String, dynamic>{},
      },
      super(Client());

  final Map<String, Map<String, dynamic>> prefsByStudent;

  /// Whose account this device's session belongs to, or null when nobody is
  /// signed in.
  String? session = _studentA;

  /// The signed-in account's preferences.
  Map<String, dynamic> get prefs => prefsByStudent[_signedIn()]!;

  String _signedIn() {
    final student = session;
    if (student == null) throw AppwriteException('no session', 401);
    return student;
  }

  /// When set, the next [getPrefs] call snapshots the preferences as they are
  /// when it is made, then waits for this before answering - a read whose
  /// response arrives after writes that landed while it was out, or after the
  /// session has changed.
  Completer<void>? holdNextRead;

  @override
  Future<models.Preferences> getPrefs() async {
    final snapshot = Map<String, dynamic>.from(prefs);
    final hold = holdNextRead;
    holdNextRead = null;
    if (hold != null) await hold.future;
    return models.Preferences(data: snapshot);
  }

  @override
  Future<models.User> updatePrefs({required Map prefs}) async {
    final student = _signedIn();
    prefsByStudent[student] = Map<String, dynamic>.from(prefs);
    return _user(student);
  }
}

/// A [NotificationService] whose [saveTopicIntent] can be held or made to
/// fail before it runs for real against [_FakeAccount], and whose [reconcile]
/// is controlled directly by the test, so [TopicIntentNotifier] can be
/// exercised without a network, Firebase, or Appwrite Messaging - none of
/// which have any test-double support in this project (no mockito/mocktail
/// either; see the hand-written fakes throughout `test/data/services/`).
class _FakeNotificationService extends NotificationService {
  _FakeNotificationService(Map<String, dynamic> seededPrefs)
    : this._(_FakeAccount(seededPrefs));

  _FakeNotificationService._(this.account) : super.withAccount(account);

  final _FakeAccount account;

  /// Thrown from [saveTopicIntent], when set. Applies to every call unless
  /// [saveThrowsOnCall] restricts it to one specific call number (1-indexed,
  /// counted by [saveCalls]).
  Object? saveThrows;
  int? saveThrowsOnCall;
  int saveCalls = 0;

  /// The last intent a save wrote to the server.
  Map<String, bool>? lastSaved;

  /// Every map ever passed to [saveTopicIntent], in call order - including
  /// ones whose save then failed, which never reach [lastSaved].
  final List<Map<String, bool>> attemptedIntents = [];

  /// When set, the Nth call to [saveTopicIntent] (1-indexed, matching
  /// [saveCalls] after increment) waits for `saveGates[n - 1]` before
  /// proceeding. Lets a test control exactly when each call's "network
  /// response" arrives, independent of the order the calls were made in -
  /// see the finding-3 race test below.
  List<Completer<void>>? saveGates;

  @override
  Future<bool> saveTopicIntent(
    Map<String, bool> intent, {
    bool Function()? onlyIf,
  }) async {
    final call = ++saveCalls;
    final payload = Map<String, bool>.from(intent);
    attemptedIntents.add(payload);
    final gates = saveGates;
    if (gates != null && call <= gates.length) {
      await gates[call - 1].future;
    }
    final failure = saveThrows;
    if (failure != null &&
        (saveThrowsOnCall == null || saveThrowsOnCall == call)) {
      throw failure;
    }
    // The real save, against whichever account the session belongs to.
    final saved = await super.saveTopicIntent(payload, onlyIf: onlyIf);
    if (saved) lastSaved = payload;
    return saved;
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

/// Resolves the session to "nobody signed in" without a network call.
class _FakeAuthService extends AuthService {
  @override
  Future<UserModel?> getCurrentUser() async => null;
}

/// An [AuthNotifier] a test signs students in to directly.
class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier() : super(_FakeAuthService());

  void signIn(String studentId, {String campusId = '1'}) {
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

  const seededIntent = <String, dynamic>{
    'notification_topics': <String, dynamic>{
      'news': true,
      'events': true,
      'jobs': true,
      'shop': true,
    },
  };

  /// Builds a notifier for student A and waits for its constructor-triggered
  /// seed load to resolve, so `state.value` is populated before a test drives
  /// it. [signedInStudentId] reports who is signed in: student A throughout,
  /// unless a test says otherwise.
  Future<TopicIntentNotifier> buildNotifier(
    _FakeNotificationService service, {
    String? campusId = '1',
    String? Function()? signedInStudentId,
  }) async {
    final notifier = TopicIntentNotifier(
      service,
      campusId,
      studentId: _studentA,
      signedInStudentId: signedInStudentId ?? () => _studentA,
    );
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
      final notifier = TopicIntentNotifier(
        service,
        '1',
        studentId: _studentA,
        signedInStudentId: () => _studentA,
      );

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
      'a queued save is built on what the server has confirmed, so a later '
      "call does not resurrect an earlier call's change after that change "
      'failed (finding 3): the failed "news" change must not be dragged '
      'along by the "events" save that runs after it',
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
      'a successful save never writes the switches back, so it cannot revert '
      "a *different* topic's optimistic flip still queued behind it "
      "(finding 3): 'events' must stay off the instant 'news' finishes "
      "saving, even though 'events' has not even been attempted yet",
      () async {
        final gates = [Completer<void>(), Completer<void>()];
        final service = _FakeNotificationService(seededIntent)
          ..saveGates = gates;
        final notifier = await buildNotifier(service);

        final futureA = notifier.setTopic('news', false);
        // Let commit A start and reach its save call, strictly before
        // 'events' is touched below.
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
        // gates[1]. Writing A's own view of the switches back would revert
        // 'events' to true right here, despite 'events' playing no part in it.
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

    test(
      'a queued save carries only its own change, never a tap still queued '
      "behind it: tapping news, events and jobs while news's save was in "
      "flight used to send jobs: false inside events's save, so when jobs's "
      'own save then failed the switch reverted to on while the server held '
      'off - and the student was told the change had not been saved',
      () async {
        final gates = [Completer<void>(), Completer<void>(), Completer<void>()];
        final service = _FakeNotificationService(seededIntent)
          ..saveGates = gates
          ..saveThrows = Exception('offline')
          ..saveThrowsOnCall = 3;
        final notifier = await buildNotifier(service);

        final news = notifier.setTopic('news', false);
        await pumpEventQueue(); // news's save is on the wire...
        final events = notifier.setTopic('events', false);
        final jobs = notifier.setTopic('jobs', false); // ...and these queue.
        for (final gate in gates) {
          gate.complete();
        }
        final results = await Future.wait([news, events, jobs]);

        expect(results, [
          ReconcileOutcome.applied,
          ReconcileOutcome.applied,
          null,
        ]);
        expect(
          service.attemptedIntents[1],
          {'news': false, 'events': false, 'jobs': true, 'shop': true},
          reason: "events's save must not carry the jobs tap queued behind it",
        );
        final server = await service.loadTopicIntent();
        expect(server, {
          'news': false,
          'events': false,
          'jobs': true,
          'shop': true,
        });
        expect(
          notifier.state.value,
          server,
          reason: 'the switches must show exactly what the server holds',
        );
      },
    );

    test(
      'a topic turned off and back on while offline, with both saves '
      'failing, ends showing what the server still holds: each failure used '
      'to revert to the value from before its own tap, so the second one '
      'put the switch back to off while the server still had it on',
      () async {
        final gates = [Completer<void>(), Completer<void>()];
        final service = _FakeNotificationService(seededIntent)
          ..saveGates = gates
          ..saveThrows = Exception('offline');
        final notifier = await buildNotifier(service);

        final off = notifier.setTopic('news', false);
        await pumpEventQueue(); // off's save is on the wire.
        final on = notifier.setTopic('news', true);
        for (final gate in gates) {
          gate.complete();
        }
        final results = await Future.wait([off, on]);

        expect(results, [null, null]);
        final server = await service.loadTopicIntent();
        expect(server['news'], isTrue, reason: 'neither save landed');
        expect(
          notifier.state.value,
          server,
          reason: 'the switches must show exactly what the server holds',
        );
      },
    );

    test(
      'a topic turned off and back on, with both saves succeeding, never '
      'flicks back to off in between: the first save used to write its own '
      'value back to the switch when it landed, while the second tap was '
      'still queued',
      () async {
        final gates = [Completer<void>(), Completer<void>()];
        final service = _FakeNotificationService(seededIntent)
          ..saveGates = gates;
        final notifier = await buildNotifier(service);

        final off = notifier.setTopic('news', false);
        await pumpEventQueue(); // off's save is on the wire.
        final on = notifier.setTopic('news', true);

        final shown = <bool?>[];
        final removeListener = notifier.addListener(
          (state) => shown.add(state.value?['news']),
          fireImmediately: false,
        );

        gates[0].complete();
        await pumpEventQueue();
        expect(service.saveCalls, 2, reason: "on's save is now on the wire");
        expect(notifier.state.value?['news'], isTrue);

        gates[1].complete();
        final results = await Future.wait([off, on]);
        removeListener();

        expect(results, [ReconcileOutcome.applied, ReconcileOutcome.applied]);
        expect(
          shown,
          isNot(contains(false)),
          reason: 'the student last turned news on, so nothing may show it '
              'off again',
        );
        final server = await service.loadTopicIntent();
        expect(server['news'], isTrue);
        expect(notifier.state.value, server);
      },
    );

    test(
      'commits that run after the notifier is disposed - topicIntentProvider '
      'rebuilds it when the campus changes - still save for the same '
      'student, and complete without throwing: their saves count and '
      'accumulate, but nothing touches state and nothing reconciles the old '
      'campus',
      () async {
        final gates = [Completer<void>(), Completer<void>(), Completer<void>()];
        final service = _FakeNotificationService(seededIntent)
          ..saveGates = gates
          ..saveThrows = Exception('offline')
          ..saveThrowsOnCall = 3;
        final notifier = await buildNotifier(service);

        final news = notifier.setTopic('news', false);
        await pumpEventQueue(); // news's save is on the wire...
        final events = notifier.setTopic('events', false);
        final jobs = notifier.setTopic('jobs', false); // ...and these queue.

        notifier.dispose();
        for (final gate in gates) {
          gate.complete();
        }
        final results = await Future.wait([news, events, jobs]);

        expect(
          results,
          [ReconcileOutcome.unavailable, ReconcileOutcome.unavailable, null],
          reason: 'saved but not reconciled from here, twice; then not saved',
        );
        expect(
          service.reconcileCalls,
          0,
          reason: 'the rebuilt notifier and the launch reconciler own the '
              'new campus',
        );
        expect(await service.loadTopicIntent(), {
          'news': false,
          'events': false,
          'jobs': true,
          'shop': true,
        });
      },
    );

    test(
      'a reload leaves a tap whose save has not resolved on screen, and '
      'waits behind queued saves rather than racing them: its read could '
      'otherwise answer after a save landed and hand back the intent from '
      'before it, and with no write-back after a save nothing would put the '
      'switch right again',
      () async {
        final service = _FakeNotificationService(seededIntent);
        final notifier = await buildNotifier(service);

        final readHold = Completer<void>();
        service.account.holdNextRead = readHold;
        final reloading = notifier.refresh();
        await pumpEventQueue(); // the reload's read is out.

        final saving = notifier.setTopic('news', false);
        expect(notifier.state.value?['news'], isFalse);

        readHold.complete();
        await reloading;
        expect(
          notifier.state.value?['news'],
          isFalse,
          reason: 'the reload must not hide a tap whose save has not resolved',
        );

        expect(await saving, ReconcileOutcome.applied);
        final server = await service.loadTopicIntent();
        expect(server['news'], isFalse);
        expect(notifier.state.value, server);
      },
    );

    test(
      'a save still queued when its student signs out and another signs in '
      'is dropped, not written through the new session: it put the first '
      "student's choices, and the answered marker, into the second "
      "student's preferences, so the second student was never asked",
      () async {
        final gates = [Completer<void>()];
        final service = _FakeNotificationService(seededIntent)
          ..saveGates = gates;
        String? signedIn = _studentA;
        final notifier = await buildNotifier(
          service,
          signedInStudentId: () => signedIn,
        );

        final news = notifier.setTopic('news', false);
        await pumpEventQueue(); // news's save is held on its way...
        final events = notifier.setTopic('events', false); // ...events queues.

        // Student A signs out, and student B signs in on this device.
        service.account.session = null;
        signedIn = null;
        service.account.session = _studentB;
        signedIn = _studentB;

        final shown = <AsyncValue<Map<String, bool>>>[];
        final removeListener = notifier.addListener(
          shown.add,
          fireImmediately: false,
        );
        gates.single.complete();
        final results = await Future.wait([news, events]);
        removeListener();

        expect(results, [null, null], reason: 'neither was saved');
        expect(service.account.prefsByStudent[_studentB], isEmpty);
        expect(service.account.prefsByStudent[_studentA], seededIntent);
        expect(
          service.saveCalls,
          1,
          reason: "events's save never started: its student had gone by then",
        );
        expect(service.reconcileCalls, 0);
        expect(shown, isEmpty, reason: 'nothing was written to state either');
      },
    );

    test(
      'a save whose student changes while its read of the preferences is out '
      "is not written to the new student's account: the preferences it read "
      "and wrote back went to whichever account the session held by then",
      () async {
        final service = _FakeNotificationService(seededIntent);
        String? signedIn = _studentA;
        final notifier = await buildNotifier(
          service,
          signedInStudentId: () => signedIn,
        );

        final readHold = Completer<void>();
        service.account.holdNextRead = readHold;
        final saving = notifier.setTopic('news', false);
        await pumpEventQueue(); // its read of A's preferences is out.

        service.account.session = _studentB;
        signedIn = _studentB;
        readHold.complete();

        expect(await saving, isNull);
        expect(service.account.prefsByStudent[_studentB], isEmpty);
        expect(service.account.prefsByStudent[_studentA], seededIntent);
        expect(service.reconcileCalls, 0);
      },
    );
  });

  group('topicIntentProvider', () {
    test(
      'builds a new notifier when a different student signs in, even on the '
      'same campus, and the first student\'s queued save does not reach the '
      'second student\'s account: it rebuilt only when the campus changed',
      () async {
        final service = _FakeNotificationService(seededIntent)
          ..saveGates = [Completer<void>()];
        final auth = _TestAuthNotifier();
        final container = ProviderContainer(
          overrides: [
            notificationServiceProvider.overrideWithValue(service),
            authStateProvider.overrideWith((ref) => auth),
          ],
        );
        addTearDown(container.dispose);
        await pumpEventQueue(); // the auth notifier's own session check

        auth.signIn(_studentA);
        final forA = container.read(topicIntentProvider.notifier);
        await pumpEventQueue(); // its load
        final saving = forA.setTopic('news', false);
        await pumpEventQueue(); // held on its way to the server

        // Student B's session replaces student A's, on the same campus, with
        // no signed-out state in between whose campus would differ.
        service.account.session = _studentB;
        auth.signIn(_studentB);
        final forB = container.read(topicIntentProvider.notifier);
        expect(forB, isNot(same(forA)));

        service.saveGates!.single.complete();
        expect(await saving, isNull);
        expect(service.account.prefsByStudent[_studentB], isEmpty);

        // Student B's own changes are saved to B's account.
        await pumpEventQueue(); // B's notifier's load
        expect(await forB.setTopic('jobs', false), ReconcileOutcome.applied);
        expect(
          await service.loadTopicIntent(),
          containsPair('jobs', false),
        );
        expect(service.account.prefsByStudent[_studentA], seededIntent);
      },
    );
  });
}
