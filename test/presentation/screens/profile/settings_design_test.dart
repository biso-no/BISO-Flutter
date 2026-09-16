import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/models/app_config.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/notification_service.dart';
import 'package:biso/data/services/privacy_service.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/screens/profile/profile_screen.dart';
import 'package:biso/presentation/screens/profile/settings_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/config/app_config_provider.dart';
import 'package:biso/providers/notification/notification_provider.dart';
import 'package:biso/providers/privacy/privacy_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

/// A [TopicIntentNotifier] whose `setTopic` is scripted rather than talking
/// to a real service, so a test can assert exactly what it was called with
/// and control what it reports back.
class _FakeTopicIntentNotifier extends TopicIntentNotifier {
  _FakeTopicIntentNotifier(NotificationService service)
    : super(service, null, studentId: 'u1', signedInStudentId: () => 'u1');

  final List<(String, bool)> calls = [];

  @override
  Future<ReconcileOutcome?> setTopic(String topicId, bool enabled) async {
    calls.add((topicId, enabled));
    return ReconcileOutcome.permissionDenied;
  }
}

List<Override> _overrides({bool controllerPermissions = false}) => [
  authStateProvider.overrideWith((_) => _Auth()),
  selectedCampusProvider.overrideWithValue(_campus),
  controllerPermissionsProvider.overrideWith((_) async => controllerPermissions),
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

  testWidgets(
    'tapping Account in General closes both Settings routes, landing on Profile',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const ProfileScreen(),
        overrides: [
          ..._overrides(),
          appConfigProvider.overrideWith(
            (_) async => const AppConfig(expensesEnabled: true),
          ),
        ],
        routed: false,
      );

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      await tester.tap(find.widgetWithText(BisoListRow, 'General'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsSectionPage), findsOneWidget);

      // The account row's title is the signed-in user's name.
      await tester.tap(find.widgetWithText(BisoListRow, 'Test Student'));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.byType(SettingsSectionPage), findsNothing);
    },
  );

  testWidgets('Validator Mode row pushes /controller-mode when the user is permitted', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) =>
              const SettingsSectionPage(section: SettingsSection.general),
        ),
        GoRoute(
          path: '/controller-mode',
          builder: (context, _) => const Scaffold(body: Text('Controller Mode Screen')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(controllerPermissions: true),
        child: MaterialApp.router(
          theme: PremiumTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.widgetWithText(BisoListRow, 'Open Validator Mode'));
    await tester.pumpAndSettle();

    expect(find.text('Controller Mode Screen'), findsOneWidget);
  });

  testWidgets(
    'a permissionDenied outcome shows its snackbar and setTopic was called with the '
    'right topic and value',
    (tester) async {
      final fake = _FakeTopicIntentNotifier(_FakeNotificationService());
      await pumpBisoScreen(
        tester,
        const SettingsSectionPage(section: SettingsSection.notifications),
        overrides: [..._overrides(), topicIntentProvider.overrideWith((ref) => fake)],
      );

      final newsRow = find.ancestor(
        of: find.text('News'),
        matching: find.byType(BisoListRow),
      );
      await tester.tap(find.descendant(of: newsRow, matching: find.byType(Switch)));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Saved. Turn on notifications in your device settings to receive them.',
        ),
        findsOneWidget,
      );
      expect(fake.calls, [('news', false)]);
    },
  );
}
