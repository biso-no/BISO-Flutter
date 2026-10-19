import 'package:biso/data/models/app_config.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/models/membership_overview.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/notification_service.dart';
import 'package:biso/data/services/privacy_service.dart';
import 'package:biso/presentation/screens/profile/profile_screen.dart';
import 'package:biso/presentation/screens/profile/settings_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/config/app_config_provider.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:biso/providers/notification/notification_provider.dart';
import 'package:biso/providers/privacy/privacy_provider.dart';
import 'package:flutter/material.dart';
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
/// real Appwrite or Firebase call. Settings reads and writes topic intent and
/// the chat preference, and reads and requests the OS permission, so only
/// those methods need real answers.
class _FakeNotificationService implements NotificationService {
  _FakeNotificationService({
    this.enabled = true,
    this.permanentlyDenied = false,
    this.grantOnRequest = true,
  });

  /// Whether the OS grants notification permission.
  bool enabled;

  /// Whether the OS would still show its permission dialog.
  final bool permanentlyDenied;

  /// What the student answers in the OS dialog.
  final bool grantOnRequest;

  int requestPermissionCalls = 0;
  int openSettingsCalls = 0;

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
  Future<bool> areNotificationsEnabled() async => enabled;

  @override
  Future<bool> requestPermission() async {
    requestPermissionCalls++;
    return enabled = grantOnRequest;
  }

  @override
  Future<bool> isPermissionPermanentlyDenied() async => permanentlyDenied;

  @override
  Future<bool> openSystemNotificationSettings() async {
    openSettingsCalls++;
    return true;
  }

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

/// No membership loaded, so `_MembershipRow` never makes a real Appwrite call.
class _NoMembership extends MembershipOverviewNotifier {
  @override
  Future<MembershipOverview?> build() async => null;
}

List<Override> _overrides({_FakeNotificationService? notifications}) => [
  authStateProvider.overrideWith((_) => _Auth()),
  selectedCampusProvider.overrideWithValue(_campus),
  notificationServiceProvider.overrideWithValue(
    notifications ?? _FakeNotificationService(),
  ),
  privacyServiceProvider.overrideWithValue(_FakePrivacyService()),
  membershipOverviewProvider.overrideWith(_NoMembership.new),
];

void main() {
  // The real ThemeModeNotifier, LocaleNotifier and AppSettingsNotifier all
  // read SharedPreferences on construction; without a mock, getInstance()
  // throws (no platform channel handler is registered in flutter_test).
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('Settings builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const SettingsScreen(),
      overrides: _overrides(),
    );
  });

  for (final section in SettingsSection.values) {
    testWidgets(
      '${section.name} section page builds on BisoPage in every appearance',
      (tester) async {
        await expectBuildsCleanly(
          tester,
          () => SettingsSectionPage(section: section),
          overrides: _overrides(),
        );
      },
    );
  }

  testWidgets('settings lists five sections and each opens its page', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const SettingsScreen(),
      overrides: _overrides(),
    );
    for (final title in [
      'General',
      'Notifications',
      'Privacy',
      'Chat',
      'Language',
    ]) {
      await tester.tap(find.widgetWithText(BisoListRow, title));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('biso-compact-title')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('biso-compact-title')))
            .data,
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

  testWidgets('Settings no longer offers Validator Mode', (tester) async {
    await pumpBisoScreen(
      tester,
      const SettingsSectionPage(section: SettingsSection.general),
      overrides: _overrides(),
    );
    expect(find.text('Validator Mode'), findsNothing);
    expect(find.text('Open Validator Mode'), findsNothing);
  });

  testWidgets(
    'a permissionDenied outcome shows its snackbar and setTopic was called with the '
    'right topic and value',
    (tester) async {
      final fake = _FakeTopicIntentNotifier(_FakeNotificationService());
      await pumpBisoScreen(
        tester,
        const SettingsSectionPage(section: SettingsSection.notifications),
        overrides: [
          ..._overrides(),
          topicIntentProvider.overrideWith((ref) => fake),
        ],
      );

      final newsRow = find.ancestor(
        of: find.text('News'),
        matching: find.byType(BisoListRow),
      );
      await tester.tap(
        find.descendant(of: newsRow, matching: find.byType(Switch)),
      );
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

  group('notifications section', () {
    const turnOn = 'Turn on notifications';

    Future<void> pumpNotifications(
      WidgetTester tester,
      _FakeNotificationService notifications,
    ) => pumpBisoScreen(
      tester,
      const SettingsSectionPage(section: SettingsSection.notifications),
      overrides: _overrides(notifications: notifications),
    );

    testWidgets('offers no way to turn notifications on while they are on', (
      tester,
    ) async {
      await pumpNotifications(tester, _FakeNotificationService());
      expect(find.text(turnOn), findsNothing);
    });

    testWidgets(
      'offers to turn notifications on while they are off, and asks for '
      'permission when tapped: a student who declined in the prompt, which '
      'never comes back, had no way to turn them on in the app',
      (tester) async {
        final notifications = _FakeNotificationService(enabled: false);
        await pumpNotifications(tester, notifications);
        expect(find.text(turnOn), findsOneWidget);

        await tester.tap(find.text(turnOn));
        await tester.pumpAndSettle();

        expect(notifications.requestPermissionCalls, 1);
        expect(notifications.openSettingsCalls, 0);
        expect(find.text(turnOn), findsNothing, reason: 'now granted');
      },
    );

    testWidgets(
      'opens the system settings instead when the system no longer shows its '
      'permission dialog',
      (tester) async {
        final notifications = _FakeNotificationService(
          enabled: false,
          permanentlyDenied: true,
        );
        await pumpNotifications(tester, notifications);

        await tester.tap(find.text(turnOn));
        await tester.pumpAndSettle();

        expect(notifications.openSettingsCalls, 1);
        expect(notifications.requestPermissionCalls, 0);
      },
    );

    testWidgets(
      'offers the system settings when the request leaves notifications off',
      (tester) async {
        final notifications = _FakeNotificationService(
          enabled: false,
          grantOnRequest: false,
        );
        await pumpNotifications(tester, notifications);

        await tester.tap(find.text(turnOn));
        await tester.pumpAndSettle();
        expect(notifications.requestPermissionCalls, 1);
        expect(find.text(turnOn), findsOneWidget);

        await tester.tap(find.text('Open settings'));
        await tester.pumpAndSettle();
        expect(notifications.openSettingsCalls, 1);
      },
    );

    testWidgets(
      'says that important announcements are always on, with nothing to '
      'switch: every device that allows notifications gets them',
      (tester) async {
        await pumpNotifications(tester, _FakeNotificationService());

        final row = find.ancestor(
          of: find.text('Important announcements'),
          matching: find.byType(BisoListRow),
        );
        expect(row, findsOneWidget);
        expect(
          find.descendant(
            of: row,
            matching: find.textContaining('Always on'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row, matching: find.byType(Switch)),
          findsNothing,
        );
      },
    );
  });
}
