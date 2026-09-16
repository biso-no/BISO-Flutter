import 'package:biso/data/models/app_config.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/models/membership_overview.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/presentation/screens/profile/profile_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/config/app_config_provider.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
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

class _FixedOverview extends MembershipOverviewNotifier {
  _FixedOverview(this.value);

  final MembershipOverview? value;

  @override
  Future<MembershipOverview?> build() async => value;

  @override
  Future<void> refresh({bool force = true}) async {}
}

MembershipOverview _overview(
  MembershipGateState state, {
  bool isMember = false,
}) => MembershipOverview(
  state: state,
  isMember: isMember,
  checkedAt: DateTime(2026, 9, 15),
);

List<Override> _overrides(MembershipOverview? overview) => [
  authStateProvider.overrideWith((_) => _Auth()),
  selectedCampusProvider.overrideWithValue(_campus),
  appConfigProvider.overrideWith(
    (_) async => const AppConfig(expensesEnabled: true),
  ),
  membershipOverviewProvider.overrideWith(() => _FixedOverview(overview)),
];

BisoListRow _membershipRow(WidgetTester tester) => tester.widget<BisoListRow>(
  find.byWidgetPredicate(
    (widget) => widget is BisoListRow && widget.title == 'Membership',
    skipOffstage: false,
  ),
);

void main() {
  testWidgets(
    'a membership check that failed is not reported as "not a member"',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const ProfileScreen(),
        overrides: _overrides(_overview(MembershipGateState.checkUnavailable)),
      );
      await tester.pumpAndSettle();

      final row = _membershipRow(tester);
      // The server says `membership_check_unavailable` precisely so the app
      // does not have to guess. Guessing "Not a member" here would state as
      // fact the one thing the check could not establish.
      expect(row.subtitle, "We couldn't check your membership");
      // Still the way in to the full screen, where they can retry.
      expect(row.onTap, isNotNull);
    },
  );

  testWidgets('a student the server says is not a member reads as one', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const ProfileScreen(),
      overrides: _overrides(_overview(MembershipGateState.eligible)),
    );
    await tester.pumpAndSettle();

    expect(_membershipRow(tester).subtitle, 'Not a member');
  });
}
