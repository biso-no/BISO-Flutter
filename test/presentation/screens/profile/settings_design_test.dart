import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/notification_service.dart';
import 'package:biso/data/services/privacy_service.dart';
import 'package:biso/presentation/screens/profile/settings_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/notification/notification_provider.dart';
import 'package:biso/providers/privacy/privacy_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/biso_screen_harness.dart';

const _campus = CampusModel(
  id: 'oslo',
  name: 'Oslo',
  description: 'Test campus',
  location: 'Oslo',
  imageUrl: '',
  heroImageUrl: '',
  stats: CampusStats(),
);

const _user = UserModel(
  id: 'u1',
  name: 'Test Student',
  email: 'student@bi.no',
  campusId: '1',
);

/// A signed-in user, mirroring the `_Auth` pattern in profile_design_test.dart.
class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth() : super(const AuthState(isAuthenticated: true, user: _user));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A [NotificationService] fake so the notifications section never makes a
/// real Appwrite or Firebase call. Settings only reads and writes topic
/// intent and the chat preference, so only those methods need real answers.
class _FakeNotificationService implements NotificationService {
  @override
  Future<Map<String, bool>> loadTopicIntent() async => const {
    'news': true,
    'events': true,
    'jobs': false,
    'shop': true,
  };

  @override
  Future<bool> saveTopicIntent(
    Map<String, bool> intent, {
    bool Function()? onlyIf,
  }) async => true;

  @override
  Future<ReconcileOutcome> reconcile({required String? campusId}) async =>
      ReconcileOutcome.applied;

  @override
  Future<bool> getChatNotificationPreference() async => true;

  @override
  Future<void> updateChatNotificationPreference(bool enabled) async {}

  @override
  Future<bool> areNotificationsEnabled() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A [PrivacyService] fake so the privacy section never makes a real
/// Appwrite call.
class _FakePrivacyService implements PrivacyService {
  @override
  Future<bool?> getUserPrivacySetting(String userId) async => true;

  @override
  Future<String> getPrivacyStatusDescription(String userId) async =>
      'Public profile - visible in search';

  @override
  Future<bool> setUserPrivacySetting(
    String userId,
    bool isPublic, {
    UserModel? userData,
  }) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> _overrides() => [
  authStateProvider.overrideWith((_) => _Auth()),
  selectedCampusProvider.overrideWithValue(_campus),
  controllerPermissionsProvider.overrideWith((_) async => false),
  notificationServiceProvider.overrideWithValue(_FakeNotificationService()),
  privacyServiceProvider.overrideWithValue(_FakePrivacyService()),
];

void main() {
  // The real ThemeModeNotifier, LocaleNotifier and AppSettingsNotifier all
  // read SharedPreferences on construction; without a mock, getInstance()
  // throws (no platform channel handler is registered in flutter_test).
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('Settings builds on BisoPage in every appearance', (tester) async {
    await expectBuildsCleanly(
      tester,
      () => const SettingsScreen(),
      overrides: _overrides(),
    );
  });

  for (final section in SettingsSection.values) {
    testWidgets('${section.name} section page builds on BisoPage in every appearance', (
      tester,
    ) async {
      await expectBuildsCleanly(
        tester,
        () => SettingsSectionPage(section: section),
        overrides: _overrides(),
      );
    });
  }

  testWidgets('settings lists five sections and each opens its page', (tester) async {
    await pumpBisoScreen(tester, const SettingsScreen(), overrides: _overrides());
    for (final title in ['General', 'Notifications', 'Privacy', 'Chat', 'Language']) {
      await tester.tap(find.widgetWithText(BisoListRow, title));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('biso-compact-title')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('biso-compact-title'))).data,
        title,
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
    }
  });
}
