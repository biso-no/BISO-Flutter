import 'dart:async';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/auth_service.dart';
import 'package:biso/data/services/device_subscription_store.dart';
import 'package:biso/data/services/notification_service.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Resolves the session to "nobody signed in" without a network call, and
/// records sign-outs instead of deleting a session.
class _FakeAuthService extends AuthService {
  int logoutCalls = 0;

  @override
  Future<UserModel?> getCurrentUser() async => null;

  @override
  Future<void> logout() async => logoutCalls++;
}

/// A [NotificationService] with nothing registered on this device, whose
/// Firebase calls can be made to never answer.
class _StuckService extends NotificationService {
  _StuckService({this.reconcileHangs = false, this.tokenDeletionHangs = false})
    : super.withAccount(Account(Client()));

  /// Whether a reconcile never gets past its permission check.
  final bool reconcileHangs;

  /// Whether deleting the FCM token never answers.
  final bool tokenDeletionHangs;

  final Completer<void> _never = Completer<void>();

  @override
  Future<bool> checkPlatformPermission() async {
    if (reconcileHangs) await _never.future;
    return true;
  }

  @override
  Future<void> deletePlatformToken() async {
    if (tokenDeletionHangs) await _never.future;
  }
}

class _ThrowingCleanupService extends NotificationService {
  _ThrowingCleanupService() : super.withAccount(Account(Client()));

  @override
  Future<void> clearToken() async => throw StateError('cleanup exploded');
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

  group('AuthNotifier.logout', () {
    testWidgets(
      'signs the student out at kSignOutCleanupTimeout when the notification '
      'cleanup hangs, leaving the pending token invalidation recorded so the '
      'next launch retries it: once sign-out joined the queue, a hung cleanup '
      'would otherwise have hung sign-out forever',
      (tester) async {
        final authService = _FakeAuthService();
        final notifier = AuthNotifier(
          authService,
          notificationService: _StuckService(tokenDeletionHangs: true),
        );
        await tester.pump();

        var signedOut = false;
        unawaited(notifier.logout().then((_) => signedOut = true));

        await tester.pump(kSignOutCleanupTimeout - const Duration(seconds: 1));
        expect(signedOut, isFalse, reason: 'cleanup still has time left');

        await tester.pump(const Duration(seconds: 1));
        expect(signedOut, isTrue);
        expect(authService.logoutCalls, 1);
        expect(notifier.state.isAuthenticated, isFalse);
        expect(notifier.state.isLoading, isFalse);
        expect(
          await DeviceSubscriptionStore().readPendingTokenInvalidation(),
          isTrue,
        );

        // The cleanup is abandoned at its own bound, and stays recorded.
        await tester.pump(kNotificationRunTimeout);
        expect(
          await DeviceSubscriptionStore().readPendingTokenInvalidation(),
          isTrue,
        );
      },
    );

    testWidgets(
      'records the pending token invalidation before sign-out stops waiting, '
      'even when the cleanup has not started because a hung reconcile is '
      'ahead of it in the queue - and the cleanup still runs afterwards',
      (tester) async {
        final authService = _FakeAuthService();
        final service = _StuckService(reconcileHangs: true);
        final notifier = AuthNotifier(
          authService,
          notificationService: service,
        );
        await tester.pump();

        unawaited(service.reconcile(campusId: '1'));
        await tester.pump();

        var signedOut = false;
        unawaited(notifier.logout().then((_) => signedOut = true));
        await tester.pump(kSignOutCleanupTimeout);

        expect(signedOut, isTrue);
        expect(authService.logoutCalls, 1);
        expect(
          await DeviceSubscriptionStore().readPendingTokenInvalidation(),
          isTrue,
        );

        // The hung reconcile is abandoned; the cleanup then runs, invalidates
        // the token, and settles what it recorded.
        await tester.pump(kNotificationRunTimeout);
        await tester.pump();
        expect(
          await DeviceSubscriptionStore().readPendingTokenInvalidation(),
          isFalse,
        );
      },
    );

    test(
      'still deletes the session when the notification cleanup throws: a '
      'cleanup failure must never leave a student unable to sign out',
      () async {
        final authService = _FakeAuthService();
        final notifier = AuthNotifier(
          authService,
          notificationService: _ThrowingCleanupService(),
        );
        await pumpEventQueue();

        await notifier.logout();

        expect(authService.logoutCalls, 1);
        expect(notifier.state.isAuthenticated, isFalse);
        expect(notifier.state.error, isNull);
      },
    );
  });
}
