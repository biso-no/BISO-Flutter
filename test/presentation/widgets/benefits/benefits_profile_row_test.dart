import 'dart:async';

import 'package:biso/data/models/app_config.dart';
import 'package:biso/data/models/campus_benefit.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/models/membership_overview.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/benefits_api_client.dart';
import 'package:biso/presentation/screens/profile/profile_screen.dart';
import 'package:biso/presentation/widgets/benefits/benefits_profile_row.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/benefits/benefits_providers.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/config/app_config_provider.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/biso_screen_harness.dart';

CampusModel _campus(String id, String name) => CampusModel(
  id: id,
  name: name,
  description: '',
  location: name,
  imageUrl: '',
  heroImageUrl: '',
  stats: const CampusStats(),
);

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth(UserModel user)
    : super(
        AuthState(isAuthenticated: true, user: user, isProfileComplete: true),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoMembership extends MembershipOverviewNotifier {
  @override
  Future<MembershipOverview?> build() async => null;
}

class _FakeApi implements BenefitsApi {
  _FakeApi(this.load);

  final Future<List<CampusBenefit>> Function() load;
  final campuses = <String?>[];

  @override
  Future<List<CampusBenefit>> fetchBenefits({String? campusId}) {
    campuses.add(campusId);
    return load();
  }

  @override
  Future<String> reveal(String benefitId) => throw UnimplementedError();
}

CampusBenefit _benefit(int i, BenefitSection section) => CampusBenefit(
  id: 'b$i',
  campusId: '3',
  section: section,
  title: BenefitText(nb: 'Fordel $i'),
  description: const BenefitText(nb: ''),
  redemptionType: BenefitRedemptionType.onsite,
);

/// 25 deals and two career perks: 27 benefits.
final _twentySeven = [
  for (var i = 0; i < 25; i++) _benefit(i, BenefitSection.member),
  _benefit(25, BenefitSection.career),
  _benefit(26, BenefitSection.career),
];

const _student = UserModel(id: 'u1', name: 'Kari', email: 'kari@bi.no');

final _benefitsStub = GoRoute(
  path: '/explore/benefits',
  builder: (_, state) => Scaffold(body: Text('benefits ${state.uri}')),
);

/// Profile, with Oslo as the Home campus and [user]'s own campus saved on
/// the profile.
Future<_FakeApi> _pump(
  WidgetTester tester, {
  required Future<List<CampusBenefit>> Function() load,
  UserModel user = _student,
}) async {
  final api = _FakeApi(load);
  await pumpBisoScreen(
    tester,
    const ProfileScreen(),
    routed: true,
    locale: const Locale('no'),
    extraRoutes: [_benefitsStub],
    overrides: [
      authStateProvider.overrideWith((_) => _Auth(user)),
      filterCampusProvider.overrideWithValue(_campus('1', 'Oslo')),
      switcherCampusesProvider.overrideWith(
        (_) async => [_campus('1', 'Oslo'), _campus('3', 'Trondheim')],
      ),
      appConfigProvider.overrideWith((_) async => const AppConfig()),
      membershipOverviewProvider.overrideWith(_NoMembership.new),
      benefitsApiProvider.overrideWithValue(api),
    ],
  );
  await tester.pump();
  return api;
}

Finder get _row => find.byType(BenefitsProfileRow);

BisoListRow _listRow(WidgetTester tester) => tester.widget<BisoListRow>(
  find.descendant(of: _row, matching: find.byType(BisoListRow)),
);

void main() {
  testWidgets('Profile row shows "27 fordeler i Trondheim" and pushes '
      '/explore/benefits?campus=3', (tester) async {
    final api = await _pump(
      tester,
      load: () async => _twentySeven,
      user: _student.copyWith(campusId: '3'),
    );

    // The profile campus, not the Home campus.
    expect(api.campuses, ['3']);
    final row = _listRow(tester);
    expect(row.title, 'Medlemsfordeler');
    expect(row.subtitle, '27 fordeler i Trondheim');
    final tile = row.leading! as BisoIconTile;
    expect(tile.icon, CupertinoIcons.gift);
    expect(tile.accent, BisoAccent.gold);

    // Right after Medlemskap and Medlemskort.
    final titles = tester
        .widgetList<BisoListRow>(find.byType(BisoListRow))
        .map((r) => r.title)
        .toList();
    final pass = titles.indexOf('Medlemskort');
    expect(titles[pass - 1], 'Membership');
    expect(titles[pass + 1], 'Medlemsfordeler');

    await tester.tap(find.text('Medlemsfordeler'));
    await tester.pumpAndSettle();
    expect(find.text('benefits /explore/benefits?campus=3'), findsOneWidget);
  });

  testWidgets(
    'a user with no campus pushes ?campus=national and shows "Hele BISO"',
    (tester) async {
      final api = await _pump(tester, load: () async => _twentySeven);
      expect(api.campuses, [null]);
      expect(_listRow(tester).subtitle, '27 fordeler i Hele BISO');

      await tester.tap(find.text('Medlemsfordeler'));
      await tester.pumpAndSettle();
      expect(
        find.text('benefits /explore/benefits?campus=national'),
        findsOneWidget,
      );
    },
  );

  testWidgets('no subtitle while loading', (tester) async {
    await _pump(tester, load: () => Completer<List<CampusBenefit>>().future);
    expect(_listRow(tester).title, 'Medlemsfordeler');
    expect(_listRow(tester).subtitle, isNull);
  });

  testWidgets('no subtitle after an error other than notDeployed', (
    tester,
  ) async {
    await _pump(
      tester,
      load: () async =>
          throw const BenefitsApiException(BenefitsApiErrorKind.network),
    );
    expect(_listRow(tester).title, 'Medlemsfordeler');
    expect(_listRow(tester).subtitle, isNull);
  });

  testWidgets('hidden on notDeployed, with no divider left behind', (
    tester,
  ) async {
    await _pump(
      tester,
      load: () async => throw const BenefitsApiException(
        BenefitsApiErrorKind.notDeployed,
        statusCode: 404,
      ),
    );
    expect(find.text('Medlemsfordeler'), findsNothing);
    expect(_row, findsNothing);
    expect(find.text('Medlemskort'), findsOneWidget);
  });
}
