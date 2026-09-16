import 'package:biso/data/models/app_config.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/models/membership_overview.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/app_config_service.dart';
import 'package:biso/presentation/screens/explore/explore_screen.dart';
import 'package:biso/presentation/screens/profile/profile_screen.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/campus/campus_data_provider.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/config/app_config_provider.dart';
import 'package:biso/providers/large_event/large_event_provider.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:biso/providers/ui/locale_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

/// Where a student finds reimbursements. After an offline launch the app
/// does not know whether BISO has them switched on — which is not the same
/// as knowing they are off, so the ways in must stay and lead to the page
/// that says so and offers to try again. Only BISO saying "off" hides them.

const _campus = CampusModel(
  id: 'oslo',
  name: 'Oslo',
  description: 'Test campus',
  location: 'Oslo',
  imageUrl: '',
  heroImageUrl: '',
  stats: CampusStats(),
);

const _user = UserModel(id: 'u1', name: 'Test Student', email: 'student@bi.no');

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth()
    : super(
        const AuthState(
          isAuthenticated: true,
          user: _user,
          isProfileComplete: true,
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoMembership extends MembershipOverviewNotifier {
  @override
  Future<MembershipOverview?> build() async => null;
}

class _Locale extends LocaleNotifier {}

Override _configFailed() => appConfigProvider.overrideWith(
  (_) async => throw const AppConfigUnavailableException(),
);

Override _switchedOff() => appConfigProvider.overrideWith(
  (_) async => const AppConfig(expensesEnabled: false),
);

List<Override> _explore(Override config) => [
  filterCampusProvider.overrideWithValue(_campus),
  campusInitializedProvider.overrideWithValue(true),
  currentCampusDataProvider.overrideWithValue(const AsyncValue.data(null)),
  featuredLargeEventProvider.overrideWithValue(null),
  localeProvider.overrideWith((ref) => _Locale()),
  config,
];

List<Override> _profile(Override config) => [
  authStateProvider.overrideWith((_) => _Auth()),
  selectedCampusProvider.overrideWithValue(_campus),
  membershipOverviewProvider.overrideWith(_NoMembership.new),
  config,
];

final _exploreEntry = find.text('Expense reimbursements', skipOffstage: false);
final _profileEntry = find.text('Expense History', skipOffstage: false);

void main() {
  testWidgets('Explore keeps reimbursements when the config could not load', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const ExploreScreen(),
      overrides: _explore(_configFailed()),
    );
    await tester.pumpAndSettle();

    expect(_exploreEntry, findsOneWidget);
  });

  testWidgets('Explore hides reimbursements when BISO switched them off', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const ExploreScreen(),
      overrides: _explore(_switchedOff()),
    );
    await tester.pumpAndSettle();

    expect(_exploreEntry, findsNothing);
  });

  testWidgets('Profile keeps expense history when the config could not load', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const ProfileScreen(),
      overrides: _profile(_configFailed()),
    );
    await tester.pumpAndSettle();

    expect(_profileEntry, findsOneWidget);
  });

  testWidgets('Profile hides expense history when BISO switched it off', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const ProfileScreen(),
      overrides: _profile(_switchedOff()),
    );
    await tester.pumpAndSettle();

    expect(_profileEntry, findsNothing);
  });
}
