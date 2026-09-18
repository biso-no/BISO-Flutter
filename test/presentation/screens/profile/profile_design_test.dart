import 'package:biso/core/constants/app_constants.dart';
import 'package:biso/data/models/app_config.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/models/membership_overview.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/presentation/screens/profile/edit_profile_screen.dart';
import 'package:biso/presentation/screens/profile/profile_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/config/app_config_provider.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  phone: '12345678',
  address: 'Testveien 1',
  city: 'Oslo',
  zipCode: '0170',
  departments: ['BISO Oslo'],
);

/// A signed-in, profile-complete user, mirroring the `_Auth` pattern in
/// navigation_content_clearance_test.dart.
class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth({bool isProfileComplete = true, UserModel user = _user})
    : super(
        AuthState(
          isAuthenticated: true,
          user: user,
          isProfileComplete: isProfileComplete,
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// No membership loaded, so `_MembershipRow` never makes a real Appwrite call.
class _NoMembership extends MembershipOverviewNotifier {
  @override
  Future<MembershipOverview?> build() async => null;
}

List<Override> _overrides({
  bool isProfileComplete = true,
  UserModel user = _user,
}) => [
  authStateProvider.overrideWith(
    (_) => _Auth(isProfileComplete: isProfileComplete, user: user),
  ),
  selectedCampusProvider.overrideWithValue(_campus),
  appConfigProvider.overrideWith(
    (_) async => const AppConfig(expensesEnabled: true),
  ),
  membershipOverviewProvider.overrideWith(_NoMembership.new),
];

void main() {
  testWidgets('Profile builds on BisoPage in every appearance', (tester) async {
    await expectBuildsCleanly(
      tester,
      () => const ProfileScreen(),
      overrides: _overrides(),
    );
  });

  testWidgets('profile rows use accent tiles and sign out is destructive', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const ProfileScreen(),
      overrides: _overrides(),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Settings'), findsOneWidget);
    // "Sign Out" sits below the fold of this long list, past the scroll
    // view's cache extent, so the default skipOffstage:true finder used by
    // the recipe's snippet would report it as not found even though it is
    // mounted; skipOffstage:false looks at the full element tree instead.
    final signOut = tester.widget<BisoListRow>(
      find.ancestor(
        of: find.text('Sign Out', skipOffstage: false),
        matching: find.byType(BisoListRow, skipOffstage: false),
      ),
    );
    expect(signOut.destructive, isTrue);
  });

  testWidgets(
    'Complete Profile opens Edit Profile filled with the saved profile',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const ProfileScreen(),
        overrides: _overrides(isProfileComplete: false),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Complete Profile'));
      await tester.pumpAndSettle();

      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Test Student'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextFormField, 'Testveien 1'), findsOneWidget);
    },
  );

  testWidgets(
    "shows the profile's saved campus, not the campus the app filters by",
    (tester) async {
      // The filter campus is Oslo (_campus); the profile says Bergen.
      await pumpBisoScreen(
        tester,
        const ProfileScreen(),
        overrides: _overrides(
          user: _user.copyWith(campusId: AppConstants.bergenId),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('BI Bergen', skipOffstage: false), findsNWidgets(2));
      expect(find.text('BI Oslo', skipOffstage: false), findsNothing);
    },
  );
}
