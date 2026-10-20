import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:biso/data/services/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A stand-in `Account` - never touched, because every method
/// [_FakeNotificationService]'s tests exercise is overridden directly below.
class _UnusedAccount extends Account {
  _UnusedAccount() : super(Client());
}

/// Overrides the two seams [NotificationService.requestPermission] cannot
/// otherwise be tested through: the OS/Firebase permission dialog (via
/// [requestPlatformPermission] - see its doc comment for why this project has
/// no fake for the real thing) and [reconcile] (which talks to Firebase
/// Messaging directly). Everything else in `requestPermission` - specifically,
/// that a grant must reconcile this device - is the real implementation.
class _FakeNotificationService extends NotificationService {
  _FakeNotificationService() : super.withAccount(_UnusedAccount());

  /// What [requestPlatformPermission] returns - stands in for the OS dialog
  /// and Firebase's own permission call both having been granted.
  bool granted = true;

  @override
  Future<bool> requestPlatformPermission() async => granted;

  /// Every campus id [reconcile] was called with, in call order.
  final List<String?> reconcileCampusIds = <String?>[];
  int get reconcileCalls => reconcileCampusIds.length;

  ReconcileOutcome reconcileResult = ReconcileOutcome.applied;

  /// Thrown from [reconcile] instead of returning [reconcileResult], when set.
  Object? reconcileThrows;

  /// When true, [reconcile] runs the real implementation instead - the only
  /// way to have it cache a campus id, as an earlier run in the session would.
  bool delegateReconcile = false;

  /// What the OS reports as the current permission. Only read by the real
  /// [reconcile] (when [delegateReconcile] is set) and by
  /// [reconcileIfPermissionNewlyGranted]. Reporting "not granted" ends a real
  /// run straight after its read of the device store (mocked below), before
  /// Firebase or Appwrite.
  bool permitted = false;

  @override
  Future<bool> checkPlatformPermission() async => permitted;

  /// No FCM token to be had: a real run that gets past the permission check
  /// ends here, unavailable.
  @override
  Future<String?> fetchPlatformToken() async =>
      throw Exception('SERVICE_NOT_AVAILABLE');

  @override
  Future<ReconcileOutcome> reconcile({
    required String? campusId,
    required String locale,
  }) async {
    reconcileCampusIds.add(campusId);
    if (delegateReconcile) {
      return super.reconcile(campusId: campusId, locale: locale);
    }
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

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('requestPermission', () {
    test(
      'reconciles this device when permission is granted (finding 4): '
      'granting from anywhere other than the first-run prompt - e.g. the '
      'chat settings toggle, which calls only this method - must still '
      'subscribe this device, not just resolve a push target and stop',
      () async {
        final service = _FakeNotificationService()..granted = true;

        final result = await service.requestPermission();

        expect(result, isTrue);
        expect(service.reconcileCalls, 1);
      },
    );

    test('does not reconcile when permission is denied - there is nothing yet '
        'to subscribe', () async {
      final service = _FakeNotificationService()..granted = false;

      final result = await service.requestPermission();

      expect(result, isFalse);
      expect(service.reconcileCalls, 0);
    });

    test('still reports the permission as granted even when reconcile could '
        'not fully update this device - reconcile is best-effort here, and a '
        'partiallyFailed subscribe must not be mistaken for a denied '
        'permission', () async {
      final service = _FakeNotificationService()
        ..granted = true
        ..reconcileResult = ReconcileOutcome.partiallyFailed;

      final result = await service.requestPermission();

      expect(result, isTrue);
      expect(service.reconcileCalls, 1);
    });

    test('reports a genuine grant as granted even when reconcile throws, and '
        'reconciles against the campus this device was last reconciled for: '
        'subscribing is best-effort here, and a throw from it - e.g. getToken '
        'failing when the launch token fetch already had - used to be caught '
        'as a failed permission request, telling a student who had just '
        'granted permission to enable it in system settings and leaving their '
        'chat notifications off', () async {
      final service = _FakeNotificationService()..delegateReconcile = true;
      // Earlier in the session, the launch reconciler reconciled campus 3.
      // requestPermission takes no campus, so that is all it has to go on.
      await service.reconcile(campusId: '3', locale: 'en');

      service
        ..delegateReconcile = false
        ..reconcileThrows = Exception('getToken: SERVICE_NOT_AVAILABLE');
      final result = await service.requestPermission();

      expect(result, isTrue);
      expect(service.reconcileCampusIds, ['3', '3']);
    });
  });

  group('reconcileIfPermissionNewlyGranted', () {
    test('reconciles once when notifications were turned on in the system '
        'settings after a reconcile found them off: nothing else reconciles '
        'when the student comes back, so this device stayed unsubscribed '
        'until the next launch', () async {
      final service = _FakeNotificationService()..delegateReconcile = true;
      // The launch reconciler finds notifications off.
      expect(
        await service.reconcile(campusId: '3', locale: 'en'),
        ReconcileOutcome.permissionDenied,
      );
      service.delegateReconcile = false;

      // The student turns them on in the system settings, and comes back.
      service.permitted = true;
      expect(
        await service.reconcileIfPermissionNewlyGranted(
          campusId: '3',
          locale: 'en',
        ),
        ReconcileOutcome.applied,
      );
      expect(service.reconcileCampusIds, ['3', '3']);

      // Back again, with nothing changed.
      expect(
        await service.reconcileIfPermissionNewlyGranted(
          campusId: '3',
          locale: 'en',
        ),
        isNull,
      );
      expect(service.reconcileCalls, 2);
    });

    test('does not reconcile again for a grant made in the app, which has '
        'reconciled already', () async {
      final service = _FakeNotificationService()..granted = true;
      expect(await service.requestPermission(), isTrue);
      expect(service.reconcileCalls, 1);

      service.permitted = true;
      expect(
        await service.reconcileIfPermissionNewlyGranted(
          campusId: '1',
          locale: 'en',
        ),
        isNull,
      );
      expect(service.reconcileCalls, 1);
    });

    test(
      'retries on the next resume when a reconcile that had permission could '
      'not finish: recording the grant left every later resume believing '
      'this device was done, so a run that found no token or no push target '
      'was not tried again until the next launch',
      () async {
        final service = _FakeNotificationService()
          ..permitted = true
          ..delegateReconcile = true;
        // The launch reconcile has permission, but no FCM token yet.
        expect(
          await service.reconcile(campusId: '1', locale: 'en'),
          ReconcileOutcome.unavailable,
        );
        service.delegateReconcile = false;

        expect(
          await service.reconcileIfPermissionNewlyGranted(
            campusId: '1',
            locale: 'en',
          ),
          ReconcileOutcome.applied,
        );
        expect(service.reconcileCalls, 2);

        // That one finished, so nothing more until something changes.
        expect(
          await service.reconcileIfPermissionNewlyGranted(
            campusId: '1',
            locale: 'en',
          ),
          isNull,
        );
        expect(service.reconcileCalls, 2);
      },
    );

    test('does not reconcile while notifications stay off', () async {
      final service = _FakeNotificationService()..permitted = false;

      expect(
        await service.reconcileIfPermissionNewlyGranted(
          campusId: '1',
          locale: 'en',
        ),
        isNull,
      );
      expect(
        await service.reconcileIfPermissionNewlyGranted(
          campusId: '1',
          locale: 'en',
        ),
        isNull,
      );
      expect(service.reconcileCalls, 0);
    });
  });
}
