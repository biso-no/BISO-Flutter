import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/auth_service.dart';
import 'package:biso/data/services/bi_sign_in_service.dart';
import 'package:biso/data/services/bi_sync_api_client.dart';
import 'package:biso/data/services/notification_service.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _student = UserModel(id: 'u1', name: 'Kari', email: 'kari@example.com');

/// Without a connection, restores [cached]; online, the server reports no
/// session (whatever the BI sign-in left behind is not under test here).
class _FakeAuthService extends AuthService {
  _FakeAuthService(this.log, {this.cached});

  final List<String> log;
  final UserModel? cached;
  bool online = false;

  @override
  Future<UserModel?> getCurrentUser() async {
    log.add('getCurrentUser');
    if (!online) throw NetworkException('offline');
    return null;
  }

  @override
  Future<UserModel?> getCachedSessionUser() async => cached;
}

/// Answers [outcome]. Like the real service, it switches sessions (calling
/// `beforeSessionSwitch`) only once BI has answered with credentials:
/// always for a [BiSignedIn], and for a failure when [switched] says the
/// session could not be created after the switch.
class _FakeBiSignIn extends BiSignInService {
  _FakeBiSignIn(this.log, this.outcome);

  final List<String> log;
  BiSignInOutcome outcome;
  bool switched = false;

  @override
  Future<BiSignInOutcome> signIn({
    Future<void> Function()? beforeSessionSwitch,
  }) async {
    log.add('signIn');
    if (outcome is BiSignedIn || switched) await beforeSessionSwitch?.call();
    return outcome;
  }
}

class _RecordingNotifications extends NotificationService {
  _RecordingNotifications(this.log) : super.withAccount(Account(Client()));

  final List<String> log;

  @override
  Future<void> clearToken() async => log.add('clearToken');
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

  late List<String> log;

  setUp(() => log = []);

  /// A notifier signed in as [signedIn] (restored offline), or signed out.
  Future<(AuthNotifier, _FakeAuthService, _FakeBiSignIn)> start({
    UserModel? signedIn,
  }) async {
    final service = _FakeAuthService(log, cached: signedIn)
      ..online = signedIn == null;
    final bi = _FakeBiSignIn(log, const BiSignInCancelled());
    final notifier = AuthNotifier(
      service,
      notificationService: _RecordingNotifications(log),
      biSignIn: bi,
    );
    await pumpEventQueue();
    log.clear();
    return (notifier, service, bi);
  }

  test(
    'from the login screen, the session is re-read only once signed in',
    () async {
      final (auth, _, bi) = await start();
      expect(auth.state.isAuthenticated, isFalse);

      expect(await auth.signInWithBi(), isA<BiSignInCancelled>());
      expect(log, ['signIn']);

      log.clear();
      bi.outcome = const BiSignedIn(BiSyncResult(success: true));
      expect(await auth.signInWithBi(), isA<BiSignedIn>());
      expect(log, ['signIn', 'getCurrentUser']);
    },
  );

  test(
    'a signed-in student who cancels or fails BI keeps their session',
    () async {
      final (auth, service, bi) = await start(signedIn: _student);
      expect(auth.state.isAuthenticated, isTrue);
      service.online = true;

      expect(await auth.signInWithBi(), isA<BiSignInCancelled>());
      bi.outcome = const BiSignInFailed(BiSignInFailure.existingAccount);
      expect(await auth.signInWithBi(), isA<BiSignInFailed>());

      expect(log, ['signIn', 'signIn']);
      expect(auth.state.isAuthenticated, isTrue);
    },
  );

  test('a signed-in student is detached from push right before the session '
      'switch, and the new session is read', () async {
    final (auth, service, bi) = await start(signedIn: _student);
    service.online = true;
    bi.outcome = const BiSignedIn(BiSyncResult(success: true));

    await auth.signInWithBi();

    expect(log, ['signIn', 'clearToken', 'getCurrentUser']);
  });

  test('a session that could not be created after the switch is re-read, '
      'since the old one has ended', () async {
    final (auth, service, bi) = await start(signedIn: _student);
    service.online = true;
    bi
      ..outcome = const BiSignInFailed(BiSignInFailure.failed)
      ..switched = true;

    await auth.signInWithBi();

    expect(log, ['signIn', 'clearToken', 'getCurrentUser']);
    expect(auth.state.isAuthenticated, isFalse);
  });
}
