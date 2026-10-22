import 'dart:async';

import 'package:biso/core/theme/biso_page.dart';
import 'package:biso/data/models/campus_benefit.dart';
import 'package:biso/data/models/member_pass.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/auth_service.dart';
import 'package:biso/data/services/benefits_api_client.dart';
import 'package:biso/presentation/widgets/benefits/benefit_detail_sheet.dart';
import 'package:biso/presentation/screens/profile/member_pass_presentation.dart';
import 'package:biso/presentation/widgets/benefits/benefit_list_section.dart';
import 'package:biso/presentation/widgets/biso/biso.dart' show BisoSkeleton;
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/benefits/benefits_providers.dart';
import 'package:biso/providers/member_pass/member_pass_provider.dart';
import 'package:biso/providers/member_pass/member_pass_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/biso_screen_harness.dart';
import '../../../helpers/fake_member_pass_api.dart'
    show FakeScreenPresentation, activeView;

class _FakeApi implements BenefitsApi {
  _FakeApi({
    this.benefits = const [],
    this.listError,
    this.revealResult = 'CODE-1234',
    this.revealError,
  });

  final List<CampusBenefit> benefits;
  final BenefitsApiException? listError;
  final String revealResult;
  final BenefitsApiException? revealError;
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
    if (revealError != null) throw revealError!;
    return revealResult;
  }
}

class _FakePass extends MemberPassNotifier {
  _FakePass(this.view);
  final MemberPassView view;
  int retries = 0;

  @override
  MemberPassView build() => view;

  @override
  Future<void> retry() async => retries++;

  void show(MemberPassView next) => state = next;
}

_FakePass? _pass;

class _FakeAuthService extends AuthService {
  @override
  Future<UserModel?> getCurrentUser() async => null;
}

class _FakeAuth extends AuthNotifier {
  _FakeAuth(UserModel? user) : super(_FakeAuthService()) {
    state = AuthState(user: user, isAuthenticated: user != null);
  }
}

final _active = activeView();

MemberPassView _noPass(NoPassState s) =>
    MemberPassView(status: PassStatus.noPass, noPassState: s);

CampusBenefit _benefit({
  String id = 'b1',
  BenefitRedemptionType type = BenefitRedemptionType.code,
  BenefitSection section = BenefitSection.member,
  String title = 'Gratis kaffe',
}) => CampusBenefit(
  id: id,
  campusId: '1',
  section: section,
  title: BenefitText(nb: title, en: 'Free coffee'),
  description: const BenefitText(nb: 'Én kaffe per uke.'),
  terms: const BenefitText(nb: 'Gjelder hverdager.'),
  redemptionType: type,
  partner: const BenefitPartner(id: 'p1', name: 'Kaffebrenneriet'),
  publishEnd: DateTime.utc(2026, 12, 31, 12),
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
  MemberPassView? pass,
  UserModel? user = _user,
  List<Uri>? opened,
  bool openerThrows = false,
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
        path: '/profile/membership',
        builder: (_, _) => const Scaffold(body: Text('membership page')),
      ),
    ],
    overrides: [
      benefitsApiProvider.overrideWithValue(api),
      memberPassProvider.overrideWith(() => _pass = _FakePass(pass ?? _active)),
      screenPresentationProvider.overrideWithValue(FakeScreenPresentation()),
      authStateProvider.overrideWith((_) => _FakeAuth(user)),
      if (openerThrows)
        benefitLinkOpenerProvider.overrideWithValue(
          (_) async => throw Exception('no handler'),
        )
      else if (opened != null)
        benefitLinkOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
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

  testWidgets('active member reveals the code and copies it', (tester) async {
    final api = _FakeApi(benefits: [_benefit()]);
    await _pump(tester, api: api);
    String? clip;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clip = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.tap(find.text('Gratis kaffe'));
    await tester.pumpAndSettle();
    expect(find.text('Én kaffe per uke.'), findsOneWidget);
    expect(find.text('Gjelder til 31. desember 2026'), findsOneWidget);
    expect(find.text('CODE-1234'), findsNothing);
    expect(api.revealed, isEmpty);

    await tester.tap(find.text('Vis kode'));
    await tester.pumpAndSettle();
    expect(api.revealed, ['b1']);
    expect(find.text('CODE-1234'), findsOneWidget);

    await tester.tap(find.text('Kopier'));
    await tester.pump();
    expect(clip, 'CODE-1234');
    expect(find.text('Kopiert'), findsOneWidget);
  });

  testWidgets('closing and reopening the sheet forgets the code', (
    tester,
  ) async {
    final api = _FakeApi(benefits: [_benefit()]);
    await _pump(tester, api: api);
    await tester.tap(find.text('Gratis kaffe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vis kode'));
    await tester.pumpAndSettle();
    expect(find.text('CODE-1234'), findsOneWidget);

    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();
    expect(find.text('CODE-1234'), findsNothing);

    await tester.tap(find.text('Gratis kaffe'));
    await tester.pumpAndSettle();
    expect(find.text('CODE-1234'), findsNothing);
    expect(find.text('Vis kode'), findsOneWidget);
    expect(api.revealed.length, 1);
  });

  testWidgets('a non-member sees Bli medlem and cannot reveal', (tester) async {
    final api = _FakeApi(benefits: [_benefit()]);
    await _pump(tester, api: api, pass: _noPass(NoPassState.notMember));
    await tester.tap(find.text('Gratis kaffe'));
    await tester.pumpAndSettle();
    expect(find.text('Koden vises bare for medlemmer.'), findsOneWidget);
    expect(find.text('Vis kode'), findsNothing);
    await tester.tap(find.text('Bli medlem'));
    await tester.pumpAndSettle();
    expect(find.text('membership page'), findsOneWidget);
    expect(api.revealed, isEmpty);
  });

  testWidgets('a pass outage is an outage, never Bli medlem', (tester) async {
    await _pump(
      tester,
      api: _FakeApi(benefits: [_benefit()]),
      pass: _noPass(NoPassState.unavailable),
    );
    await tester.tap(find.text('Gratis kaffe'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vi får ikke sjekket'), findsOneWidget);
    expect(find.text('Bli medlem'), findsNothing);
  });

  for (final kind in [
    BenefitsApiErrorKind.rateLimited,
    BenefitsApiErrorKind.membershipUnavailable,
    BenefitsApiErrorKind.unavailable,
    BenefitsApiErrorKind.network,
    BenefitsApiErrorKind.unknown,
    BenefitsApiErrorKind.notAuthenticated,
  ]) {
    testWidgets('reveal error $kind shows the outage line with retry', (
      tester,
    ) async {
      final api = _FakeApi(
        benefits: [_benefit()],
        revealError: BenefitsApiException(kind),
      );
      await _pump(tester, api: api);
      await tester.tap(find.text('Gratis kaffe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vis kode'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Vi får ikke sjekket'), findsOneWidget);
      expect(find.text('Bli medlem'), findsNothing);
      await tester.tap(find.text('Prøv igjen'));
      await tester.pumpAndSettle();
      expect(api.revealed.length, 2);
    });
  }

  testWidgets('reveal not_member shows the members-only state', (tester) async {
    await _pump(
      tester,
      api: _FakeApi(
        benefits: [_benefit()],
        revealError: const BenefitsApiException(BenefitsApiErrorKind.notMember),
      ),
    );
    await tester.tap(find.text('Gratis kaffe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vis kode'));
    await tester.pumpAndSettle();
    expect(find.text('Koden vises bare for medlemmer.'), findsOneWidget);
    expect(find.text('Bli medlem'), findsOneWidget);
  });

  for (final kind in [
    BenefitsApiErrorKind.notFound,
    BenefitsApiErrorKind.noCode,
  ]) {
    testWidgets('reveal $kind shows not found', (tester) async {
      await _pump(
        tester,
        api: _FakeApi(
          benefits: [_benefit()],
          revealError: BenefitsApiException(kind),
        ),
      );
      await tester.tap(find.text('Gratis kaffe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vis kode'));
      await tester.pumpAndSettle();
      expect(
        find.text('Denne fordelen er ikke lenger tilgjengelig.'),
        findsOneWidget,
      );
    });
  }

  testWidgets('link benefit opens an https link', (tester) async {
    final opened = <Uri>[];
    await _pump(
      tester,
      api: _FakeApi(
        benefits: [_benefit(type: BenefitRedemptionType.link)],
        revealResult: 'https://partner.example/deal',
      ),
      opened: opened,
    );
    await tester.tap(find.text('Gratis kaffe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Åpne lenken'));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://partner.example/deal')]);
  });

  testWidgets('link benefit refuses a non-https link', (tester) async {
    final opened = <Uri>[];
    await _pump(
      tester,
      api: _FakeApi(
        benefits: [_benefit(type: BenefitRedemptionType.link)],
        revealResult: 'http://partner.example/deal',
      ),
      opened: opened,
    );
    await tester.tap(find.text('Gratis kaffe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Åpne lenken'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(
      find.text('Denne fordelen er ikke lenger tilgjengelig.'),
      findsOneWidget,
    );
  });

  testWidgets('onsite benefit points at the membership card', (tester) async {
    final api = _FakeApi(
      benefits: [_benefit(type: BenefitRedemptionType.onsite)],
    );
    await _pump(tester, api: api);
    await tester.tap(find.text('Gratis kaffe'));
    await tester.pumpAndSettle();
    expect(find.text('Vis medlemskortet i kassa'), findsOneWidget);
    expect(find.text('Vis kode'), findsNothing);
    expect(api.revealed, isEmpty);
    await tester.tap(find.text('Vis medlemskortet i kassa'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(MemberPassPresentation), findsOneWidget);
  });

  group('sheet standing', () {
    // (pass view, shows Bli medlem, outage line, sign-in hint, reveal button)
    final cases = <String, (MemberPassView, bool, bool, bool, bool)>{
      'reconnect': (
        const MemberPassView(status: PassStatus.reconnect),
        false,
        true,
        false,
        false,
      ),
      'loading': (
        const MemberPassView(status: PassStatus.loading),
        false,
        false,
        false,
        false,
      ),
      'noPass(null)': (
        const MemberPassView(status: PassStatus.noPass),
        false,
        true,
        false,
        false,
      ),
      'noPass(unavailable)': (
        _noPass(NoPassState.unavailable),
        false,
        true,
        false,
        false,
      ),
      'signedOut': (
        const MemberPassView(status: PassStatus.signedOut),
        false,
        false,
        true,
        false,
      ),
      'expired': (_noPass(NoPassState.expired), true, false, false, false),
      'noBiIdentity': (
        _noPass(NoPassState.noBiIdentity),
        true,
        false,
        false,
        false,
      ),
      'notMember': (_noPass(NoPassState.notMember), true, false, false, false),
      'active': (_active, false, false, false, true),
    };
    for (final entry in cases.entries) {
      testWidgets(entry.key, (tester) async {
        final (view, member, outage, signIn, reveal) = entry.value;
        final api = _FakeApi(benefits: [_benefit()]);
        await _pump(tester, api: api, pass: view);
        await tester.tap(find.text('Gratis kaffe'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('Bli medlem'), member ? findsOneWidget : findsNothing);
        expect(
          find.textContaining('Vi får ikke sjekket'),
          outage ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Logg inn for å se koden'),
          signIn ? findsOneWidget : findsNothing,
        );
        expect(find.text('Vis kode'), reveal ? findsOneWidget : findsNothing);
        expect(api.revealed, isEmpty);
      });
    }
  });

  testWidgets('a revealed code stays when the pass drops to reconnect', (
    tester,
  ) async {
    await _pump(tester, api: _FakeApi(benefits: [_benefit()]));
    await tester.tap(find.text('Gratis kaffe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vis kode'));
    await tester.pumpAndSettle();
    _pass!.show(const MemberPassView(status: PassStatus.reconnect));
    await tester.pumpAndSettle();
    expect(find.text('CODE-1234'), findsOneWidget);
    expect(find.textContaining('Vi får ikke sjekket'), findsNothing);
  });

  testWidgets('the outage retry asks the pass to retry', (tester) async {
    await _pump(
      tester,
      api: _FakeApi(benefits: [_benefit()]),
      pass: _noPass(NoPassState.unavailable),
    );
    await tester.tap(find.text('Gratis kaffe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prøv igjen'));
    await tester.pump();
    expect(_pass!.retries, 1);
  });

  testWidgets('a link that will not open says so, not "unavailable"', (
    tester,
  ) async {
    await _pump(
      tester,
      api: _FakeApi(
        benefits: [_benefit(type: BenefitRedemptionType.link)],
        revealResult: 'https://partner.example/deal',
      ),
      openerThrows: true,
    );
    await tester.tap(find.text('Gratis kaffe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Åpne lenken'));
    await tester.pumpAndSettle();
    expect(find.text('Klarte ikke å åpne lenken. Prøv igjen.'), findsOneWidget);
    expect(find.textContaining('Vi får ikke sjekket'), findsNothing);
  });

  testWidgets('the terms fold open', (tester) async {
    await _pump(tester, api: _FakeApi(benefits: [_benefit()]));
    await tester.tap(find.text('Gratis kaffe'));
    await tester.pumpAndSettle();
    expect(find.text('Gjelder hverdager.'), findsNothing);
    await tester.tap(find.text('Vilkår'));
    await tester.pumpAndSettle();
    expect(find.text('Gjelder hverdager.'), findsOneWidget);
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
        authStateProvider.overrideWith((_) => _FakeAuth(_user)),
      ],
    );
    expect(find.text('Dine fordeler'), findsOneWidget);
    expect(find.byType(BisoSkeleton), findsOneWidget);
    completer.complete(const []);
    await tester.pumpAndSettle();
  });
}
