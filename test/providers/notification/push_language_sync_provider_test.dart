import 'dart:ui' as ui;

import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/auth_service.dart';
import 'package:biso/data/services/profile_api_client.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/notification/push_language_sync_provider.dart';
import 'package:biso/providers/ui/locale_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _student = 'student-a';
const String _syncedKey = 'push_language_synced_$_student';

class _FakeAuthService extends AuthService {
  @override
  Future<UserModel?> getCurrentUser() async => null;
}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier() : super(_FakeAuthService());

  void signIn({required bool hasProfile}) {
    state = AuthState(
      user: UserModel(id: _student, name: _student, email: 'a@bi.no'),
      isAuthenticated: true,
      hasProfile: hasProfile,
    );
  }
}

class _FakeProfileApi extends ProfileApiClient {
  final List<Map<String, dynamic>> calls = [];
  int failuresLeft = 0;

  /// Answers like an older API that drops fields it does not know: success,
  /// with a saved profile that has no `locale`.
  bool stripsLocale = false;

  @override
  Future<Map<String, dynamic>> upsert(Map<String, dynamic> fields) async {
    calls.add(fields);
    if (failuresLeft > 0) {
      failuresLeft--;
      throw const ProfileApiException('nope');
    }
    return {
      r'$id': 'profile-1',
      'name': _student,
      ...fields,
      if (stripsLocale) 'locale': null,
    }..removeWhere((key, value) => value == null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeProfileApi api;

  Future<ProviderContainer> build({
    bool hasProfile = true,
    String device = 'nb',
    LocaleNotifier? locale,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    api = _FakeProfileApi();
    final auth = _TestAuthNotifier();
    final container = ProviderContainer(
      overrides: [
        profileApiClientProvider.overrideWithValue(api),
        authStateProvider.overrideWith((ref) => auth),
        localeProvider.overrideWith(
          (ref) =>
              locale ?? LocaleNotifier(deviceLocale: () => ui.Locale(device)),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(authStateProvider);
    await pumpEventQueue(); // let the notifier's own startup check finish.
    auth.signIn(hasProfile: hasProfile);
    return container;
  }

  test('saves the language once per user and language', () async {
    final container = await build();
    await container.read(pushLanguageSyncProvider.future);
    container.invalidate(pushLanguageSyncProvider);
    await container.read(pushLanguageSyncProvider.future);

    expect(api.calls, [
      {'locale': 'no'},
    ]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_syncedKey), 'no');
  });

  test('saves again after the language changes', () async {
    final container = await build();
    container.listen(pushLanguageSyncProvider, (_, _) {});
    await container.read(pushLanguageSyncProvider.future);

    await container.read(localeProvider.notifier).setLocale('en');
    await pumpEventQueue();
    await container.read(pushLanguageSyncProvider.future);

    expect(api.calls, [
      {'locale': 'no'},
      {'locale': 'en'},
    ]);
  });

  test('never writes for a user without a profile row', () async {
    final container = await build(hasProfile: false);
    await container.read(pushLanguageSyncProvider.future);

    expect(api.calls, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_syncedKey), isNull);
  });

  test('retries after a failed save', () async {
    final container = await build();
    api.failuresLeft = 1;
    await container.read(pushLanguageSyncProvider.future);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_syncedKey), isNull);

    container.invalidate(pushLanguageSyncProvider);
    await container.read(pushLanguageSyncProvider.future);

    expect(api.calls, hasLength(2));
    expect(prefs.getString(_syncedKey), 'no');
  });

  test(
    'does not remember the language when the saved profile comes back '
    'without it: an API that drops unknown fields still answers success',
    () async {
      final container = await build();
      api.stripsLocale = true;
      await container.read(pushLanguageSyncProvider.future);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_syncedKey), isNull);

      // Retried on the next start, and remembered once the server keeps it.
      api.stripsLocale = false;
      container.invalidate(pushLanguageSyncProvider);
      await container.read(pushLanguageSyncProvider.future);

      expect(api.calls, hasLength(2));
      expect(prefs.getString(_syncedKey), 'no');
    },
  );

  test('saves a Bokmål app language as no', () async {
    final container = await build(
      locale: LocaleNotifier(deviceLocale: () => const ui.Locale('nb')),
    );
    await container.read(pushLanguageSyncProvider.future);

    expect(api.calls, [
      {'locale': 'no'},
    ]);
  });
}
