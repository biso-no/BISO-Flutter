import 'dart:async';

import 'package:biso/core/theme/biso_page.dart';
import 'package:biso/data/models/campus_benefit.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/auth_service.dart';
import 'package:biso/data/services/benefits_api_client.dart';
import 'package:biso/presentation/widgets/benefits/benefit_list_section.dart';
import 'package:biso/presentation/widgets/biso/biso.dart' show BisoSkeleton;
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/benefits/benefits_providers.dart';
import 'package:biso/providers/member_pass/member_pass_provider.dart';
import 'package:biso/providers/member_pass/member_pass_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/biso_screen_harness.dart';
import '../../../helpers/fake_member_pass_api.dart' show activeView;

class _FakeApi implements BenefitsApi {
  _FakeApi({this.benefits = const [], this.listError});

  final List<CampusBenefit> benefits;
  final BenefitsApiException? listError;
  final campuses = <String?>[];
  final revealed = <String>[];

  @override
  Future<List<CampusBenefit>> fetchBenefits({String? campusId}) async {
    campuses.add(campusId);
    if (listError != null) throw listError!;
    return benefits;
  }

  @override
  Future<String> reveal(String benefitId) async {
    revealed.add(benefitId);
    return 'CODE-1234';
  }
}

class _FakePass extends MemberPassNotifier {
  _FakePass(this.view);
  final MemberPassView view;

  @override
  MemberPassView build() => view;
}

class _FakeAuthService extends AuthService {
  @override
  Future<UserModel?> getCurrentUser() async => null;
}

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this.user) : super(authService: _FakeAuthService());

  final UserModel? user;

  @override
  AuthState build() {
    super.build();
    return AuthState(user: user, isAuthenticated: user != null);
  }
}

final _active = activeView();

CampusBenefit _benefit({
  String id = 'b1',
  BenefitSection section = BenefitSection.member,
  String title = 'Gratis kaffe',
}) => CampusBenefit(
  id: id,
  campusId: '1',
  section: section,
  title: BenefitText(nb: title, en: 'Free coffee'),
  description: const BenefitText(nb: 'Én kaffe per uke.'),
  redemptionType: BenefitRedemptionType.code,
  partner: const BenefitPartner(id: 'p1', name: 'Kaffebrenneriet'),
);

const _user = UserModel(
  id: 'u1',
  name: 'Kari',
  email: 'kari@bi.no',
  campusId: '2',
);

Future<_FakeApi> _pump(
  WidgetTester tester, {
  required _FakeApi api,
  UserModel? user = _user,
}) async {
  await pumpBisoScreen(
    tester,
    const BisoPage(
      title: 'Pass',
      slivers: [SliverToBoxAdapter(child: BenefitListSection())],
    ),
    routed: true,
    locale: const Locale('no'),
    extraRoutes: [
      GoRoute(
        path: '/explore/benefits',
        builder: (_, state) => Scaffold(body: Text('benefits ${state.uri}')),
      ),
      GoRoute(
        path: '/explore/benefits/:benefitId',
        builder: (_, state) => Scaffold(
          body: Text(
            'deal ${state.pathParameters['benefitId']} '
            '${state.uri.queryParameters['campus']} '
            '${(state.extra as CampusBenefit?)?.id}',
          ),
        ),
      ),
    ],
    overrides: [
      benefitsApiProvider.overrideWithValue(api),
      memberPassProvider.overrideWith(() => _FakePass(_active)),
      authStateProvider.overrideWith(() => _FakeAuth(user)),
    ],
  );
  return api;
}

void main() {
  testWidgets('lists member benefits for the profile campus', (tester) async {
    final api = _FakeApi(
      benefits: [
        _benefit(),
        _benefit(id: 'b2', section: BenefitSection.career, title: 'Karriere'),
      ],
    );
    await _pump(tester, api: api);
    expect(find.text('Dine fordeler'), findsOneWidget);
    expect(find.text('Gratis kaffe'), findsOneWidget);
    expect(find.text('Kaffebrenneriet'), findsOneWidget);
    expect(find.text('Karriere'), findsNothing);
    expect(api.campuses, ['2']);
  });

  testWidgets('a missing campus asks for national benefits only', (
    tester,
  ) async {
    final api = _FakeApi(benefits: [_benefit()]);
    await _pump(tester, api: api, user: null);
    expect(api.campuses, [null]);
    expect(find.text('Gratis kaffe'), findsOneWidget);
  });

  testWidgets('empty list shows the empty copy', (tester) async {
    await _pump(tester, api: _FakeApi());
    expect(find.text('Ingen fordeler her ennå.'), findsOneWidget);
  });

  testWidgets('a route that is not deployed hides the whole section', (
    tester,
  ) async {
    await _pump(
      tester,
      api: _FakeApi(
        listError: const BenefitsApiException(BenefitsApiErrorKind.notDeployed),
      ),
    );
    expect(find.text('Dine fordeler'), findsNothing);
    expect(find.text('Prøv igjen'), findsNothing);
    expect(find.text('Vis alle'), findsNothing);
  });

  testWidgets(
    'member pass "Vis alle" pushes /explore/benefits?campus=<profile campus>',
    (tester) async {
      await _pump(tester, api: _FakeApi(benefits: [_benefit()]));
      await tester.tap(find.widgetWithText(TextButton, 'Vis alle'));
      await tester.pumpAndSettle();
      expect(find.text('benefits /explore/benefits?campus=2'), findsOneWidget);
    },
  );

  testWidgets('with no profile campus "Vis alle" pins all of BISO', (
    tester,
  ) async {
    await _pump(tester, api: _FakeApi(benefits: [_benefit()]), user: null);
    await tester.tap(find.widgetWithText(TextButton, 'Vis alle'));
    await tester.pumpAndSettle();
    expect(
      find.text('benefits /explore/benefits?campus=national'),
      findsOneWidget,
    );
  });

  testWidgets('"Vis alle" stays with an empty list or another error', (
    tester,
  ) async {
    await _pump(tester, api: _FakeApi());
    expect(find.text('Vis alle'), findsOneWidget);

    await _pump(
      tester,
      api: _FakeApi(
        listError: const BenefitsApiException(BenefitsApiErrorKind.network),
      ),
    );
    expect(find.text('Vis alle'), findsOneWidget);
  });

  testWidgets('another list error shows a retry that reloads', (tester) async {
    final api = _FakeApi(
      listError: const BenefitsApiException(BenefitsApiErrorKind.network),
    );
    await _pump(tester, api: api);
    expect(find.byType(FilledButton), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump();
    expect(api.campuses.length, 2);
  });

  testWidgets('tapping a row opens the deal page', (tester) async {
    final api = _FakeApi(benefits: [_benefit()]);
    await _pump(tester, api: api);
    await tester.tap(find.text('Gratis kaffe'));
    await tester.pumpAndSettle();
    expect(find.text('deal b1 2 b1'), findsOneWidget);
    expect(api.revealed, isEmpty);
  });

  testWidgets('shows the skeleton while loading', (tester) async {
    final completer = Completer<List<CampusBenefit>>();
    await pumpBisoScreen(
      tester,
      const BisoPage(
        title: 'Pass',
        slivers: [SliverToBoxAdapter(child: BenefitListSection())],
      ),
      locale: const Locale('no'),
      overrides: [
        campusBenefitsProvider.overrideWith((ref, _) => completer.future),
        memberPassProvider.overrideWith(() => _FakePass(_active)),
        authStateProvider.overrideWith(() => _FakeAuth(_user)),
      ],
    );
    expect(find.text('Dine fordeler'), findsOneWidget);
    expect(find.text('Vis alle'), findsOneWidget);
    expect(find.byType(BisoSkeleton), findsOneWidget);
    completer.complete(const []);
    await tester.pumpAndSettle();
  });
}
