import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:biso/data/services/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

  int reconcileCalls = 0;
  ReconcileOutcome reconcileResult = ReconcileOutcome.applied;

  @override
  Future<ReconcileOutcome> reconcile({required String? campusId}) async {
    reconcileCalls++;
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

    test(
      'does not reconcile when permission is denied - there is nothing yet '
      'to subscribe',
      () async {
        final service = _FakeNotificationService()..granted = false;

        final result = await service.requestPermission();

        expect(result, isFalse);
        expect(service.reconcileCalls, 0);
      },
    );

    test(
      'still reports the permission as granted even when reconcile could '
      'not fully update this device - reconcile is best-effort here, and a '
      'partiallyFailed subscribe must not be mistaken for a denied '
      'permission',
      () async {
        final service = _FakeNotificationService()
          ..granted = true
          ..reconcileResult = ReconcileOutcome.partiallyFailed;

        final result = await service.requestPermission();

        expect(result, isTrue);
        expect(service.reconcileCalls, 1);
      },
    );
  });
}
