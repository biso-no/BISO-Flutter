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

  /// Thrown from the next [saveTopicIntent] call, when set.
  Object? saveThrows;
  int saveCalls = 0;
  Map<String, bool>? lastSaved;

  @override
  Future<void> saveTopicIntent(Map<String, bool> intent) async {
    saveCalls++;
    final failure = saveThrows;
    if (failure != null) throw failure;
    lastSaved = intent;
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
  });
}
