import 'dart:async';

import 'package:biso/core/theme/biso_page.dart';
import 'package:biso/data/models/campus_benefit.dart';
import 'package:biso/data/models/member_pass.dart';
import 'package:biso/data/models/membership_overview.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/auth_service.dart';
import 'package:biso/data/services/benefits_api_client.dart';
import 'package:biso/data/services/bi_sign_in_service.dart';
import 'package:biso/data/services/bi_sync_api_client.dart';
import 'package:biso/presentation/screens/profile/member_pass_presentation.dart';
import 'package:biso/presentation/widgets/benefits/benefit_action_panel.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/auth/bi_sign_in_provider.dart';
import 'package:biso/providers/benefits/benefits_providers.dart';
import 'package:biso/providers/member_pass/member_pass_provider.dart';
import 'package:biso/providers/member_pass/member_pass_session.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/biso_screen_harness.dart';
import '../../../helpers/fake_member_pass_api.dart'
    show FakeScreenPresentation, activeView;
import '../../../helpers/membership_fixtures.dart';

class _FakeApi implements BenefitsApi {
  _FakeApi({this.revealResult = 'CODE-1234', this.revealError});

  final String revealResult;
  final BenefitsApiException? revealError;
  final revealed = <String>[];

  /// When set, reveals wait for it.
  Completer<String>? pending;

  @override
  Future<List<CampusBenefit>> fetchBenefits({String? campusId}) async =>
      const [];

  @override
  Future<String> reveal(String benefitId) async {
    revealed.add(benefitId);
    final wait = pending;
    if (wait != null) return wait.future;
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

class _Overview extends MembershipOverviewNotifier {
  _Overview(this.value);

  final MembershipOverview? value;
  int refreshes = 0;

  @override
  Future<MembershipOverview?> build() async => value;

  @override
  Future<void> refresh({bool force = true}) async => refreshes++;
}

/// Waits for [pending] when set.
class _FakeBiSignIn extends BiSignInService {
  int syncs = 0;
  Completer<BiSyncResult>? pending;

  @override
  Future<BiSyncResult> syncOnly() async {
    syncs++;
    final wait = pending;
    if (wait != null) return wait.future;
    return const BiSyncResult(success: true, studentId: 's1');
  }
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

_FakePass? _pass;
_Overview? _overview;
_FakeBiSignIn? _bi;

final _active = activeView();

MemberPassView _noPass(NoPassState s) =>
    MemberPassView(status: PassStatus.noPass, noPassState: s);

const _signedOut = MemberPassView(status: PassStatus.signedOut);
const _loading = MemberPassView(status: PassStatus.loading);
const _reconnect = MemberPassView(status: PassStatus.reconnect);

CampusBenefit _benefit({
  BenefitRedemptionType type = BenefitRedemptionType.code,
  String? website,
}) => CampusBenefit(
  id: 'b1',
  campusId: '1',
  section: BenefitSection.member,
  title: const BenefitText(nb: 'Gratis kaffe', en: 'Free coffee'),
  redemptionType: type,
  partner: BenefitPartner(
    id: 'p1',
    name: 'Kaffebrenneriet',
    websiteUrl: website,
  ),
);

const _user = UserModel(
  id: 'u1',
  name: 'Kari',
  email: 'kari@bi.no',
  campusId: '2',
);

Future<_FakeApi> _pump(
  WidgetTester tester, {
  _FakeApi? api,
  CampusBenefit? benefit,
  MemberPassView? pass,
  MembershipOverview? overview,
  int otherCount = 26,
  String campusName = 'Trondheim',
  List<Uri>? opened,
  bool openerThrows = false,
  ValueNotifier<bool>? shown,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) async {
  final fake = api ?? _FakeApi();
  final panel = BenefitActionPanel(
    benefit: benefit ?? _benefit(),
    otherCount: otherCount,
    campusName: campusName,
  );
  await pumpBisoScreen(
    tester,
    BisoPage(
      title: 'Tilbud',
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverToBoxAdapter(
            child: shown == null
                ? panel
                : ValueListenableBuilder<bool>(
                    valueListenable: shown,
                    builder: (_, visible, _) =>
                        visible ? panel : const SizedBox.shrink(),
                  ),
          ),
        ),
      ],
    ),
    routed: true,
    locale: const Locale('no'),
    brightness: brightness,
    textScale: textScale,
    extraRoutes: [
      GoRoute(
        path: '/profile/membership',
        builder: (_, _) => const Scaffold(body: Text('membership page')),
      ),
      GoRoute(
        path: '/auth/login',
        builder: (_, _) => const Scaffold(body: Text('login page')),
      ),
    ],
    overrides: [
      benefitsApiProvider.overrideWithValue(fake),
      memberPassProvider.overrideWith(() => _pass = _FakePass(pass ?? _active)),
      membershipOverviewProvider.overrideWith(
        () => _overview = _Overview(overview),
      ),
      authStateProvider.overrideWith(() => _FakeAuth(_user)),
      biSignInServiceProvider.overrideWithValue(_bi = _FakeBiSignIn()),
      screenPresentationProvider.overrideWithValue(FakeScreenPresentation()),
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
  return fake;
}

/// Records what the app puts on the clipboard.
void Function() _watchClipboard(
  WidgetTester tester,
  void Function(String?) on,
) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        on((call.arguments as Map)['text'] as String?);
      }
      return null;
    },
  );
  return () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    null,
  );
}

Finder get _panelText => find.descendant(
  of: find.byType(BenefitActionPanel),
  matching: find.byType(Text),
);

const _locked = 'Bare for BISO-medlemmer';
const _outage =
    'Vi får ikke sjekket medlemskapet ditt akkurat nå. Prøv igjen om litt.';
const _notFound = 'Denne fordelen er ikke lenger tilgjengelig.';

void main() {
  group('member', () {
    testWidgets('onsite: the till card opens the membership card', (
      tester,
    ) async {
      final api = await _pump(
        tester,
        benefit: _benefit(type: BenefitRedemptionType.onsite),
      );
      expect(find.text('Vis medlemskortet i kassen'), findsOneWidget);
      expect(
        find.text('Vis kortet før du betaler, så får du rabatten.'),
        findsOneWidget,
      );
      expect(find.text('Vis rabattkode'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Vis medlemskortet'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(MemberPassPresentation), findsOneWidget);
      expect(api.revealed, isEmpty);
    });

    testWidgets('none: a quiet note and no button', (tester) async {
      await _pump(tester, benefit: _benefit(type: BenefitRedemptionType.none));
      expect(find.text('Du har denne fordelen som medlem.'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('link: the pill reads "Åpne tilbudet"', (tester) async {
      await _pump(tester, benefit: _benefit(type: BenefitRedemptionType.link));
      expect(
        find.widgetWithText(FilledButton, 'Åpne tilbudet'),
        findsOneWidget,
      );
      expect(find.text('Vis rabattkode'), findsNothing);
    });

    testWidgets('reveals the code and copies it', (tester) async {
      final api = await _pump(tester);
      String? clip;
      addTearDown(_watchClipboard(tester, (text) => clip = text));
      expect(find.text('CODE-1234'), findsNothing);
      expect(api.revealed, isEmpty);

      await tester.tap(find.widgetWithText(FilledButton, 'Vis rabattkode'));
      await tester.pumpAndSettle();
      expect(api.revealed, ['b1']);
      expect(find.text('Din rabattkode'), findsOneWidget);
      expect(find.text('CODE-1234'), findsOneWidget);
      expect(
        find.text('Koden gjelder bare for BISO-medlemmer.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Kopier'));
      await tester.pump();
      expect(clip, 'CODE-1234');
      expect(find.text('Kopiert'), findsOneWidget);
    });

    testWidgets('the code is in monospace', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Vis rabattkode'));
      await tester.pumpAndSettle();
      final code = tester.widget<Text>(find.text('CODE-1234'));
      expect(code.style?.fontFamily, 'monospace');
    });

    testWidgets('"Til butikken" shows only when the partner has a website', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('Vis rabattkode'));
      await tester.pumpAndSettle();
      expect(find.text('Kopier'), findsOneWidget);
      expect(find.text('Til butikken'), findsNothing);
    });

    testWidgets('"Til butikken" opens the partner website', (tester) async {
      final opened = <Uri>[];
      await _pump(
        tester,
        benefit: _benefit(website: 'https://kaffebrenneriet.no'),
        opened: opened,
      );
      await tester.tap(find.text('Vis rabattkode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Til butikken'));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://kaffebrenneriet.no')]);
      expect(find.text('CODE-1234'), findsOneWidget);
    });

    testWidgets('a website that will not open says so and keeps the code', (
      tester,
    ) async {
      await _pump(
        tester,
        benefit: _benefit(website: 'https://kaffebrenneriet.no'),
        openerThrows: true,
      );
      await tester.tap(find.text('Vis rabattkode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Til butikken'));
      await tester.pump();
      expect(
        find.text('Klarte ikke å åpne lenken. Prøv igjen.'),
        findsOneWidget,
      );
      expect(find.text('CODE-1234'), findsOneWidget);
    });

    testWidgets('a website that is not https gets no "Til butikken"', (
      tester,
    ) async {
      await _pump(
        tester,
        benefit: _benefit(website: 'http://kaffebrenneriet.no'),
      );
      await tester.tap(find.text('Vis rabattkode'));
      await tester.pumpAndSettle();
      expect(find.text('CODE-1234'), findsOneWidget);
      expect(find.text('Til butikken'), findsNothing);
    });

    testWidgets('a second quick tap does not start another reveal', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final api = _FakeApi()..pending = Completer<String>();
      await _pump(tester, api: api);
      await tester.tap(find.text('Vis rabattkode'));
      await tester.tap(find.text('Vis rabattkode'));
      await tester.pump();
      expect(api.revealed, ['b1']);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Vis rabattkode')),
        isSemantics(
          label: 'Vis rabattkode',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
      api.pending!.complete('CODE-1234');
      await tester.pumpAndSettle();
      expect(find.text('CODE-1234'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('two quick outage retries start one reveal', (tester) async {
      final api = await _pump(
        tester,
        api: _FakeApi(
          revealError: const BenefitsApiException(
            BenefitsApiErrorKind.unavailable,
          ),
        ),
      );
      await tester.tap(find.text('Vis rabattkode'));
      await tester.pumpAndSettle();
      expect(find.text(_outage), findsOneWidget);

      api.pending = Completer<String>();
      await tester.tap(find.text('Prøv igjen'));
      await tester.tap(find.text('Prøv igjen'));
      await tester.pump();
      expect(api.revealed.length, 2);

      api.pending!.complete('CODE-1234');
      await tester.pumpAndSettle();
      expect(api.revealed.length, 2);
      expect(find.text('CODE-1234'), findsOneWidget);
    });

    testWidgets('two quick link retries start one reveal', (tester) async {
      final api = await _pump(
        tester,
        api: _FakeApi(revealResult: 'https://partner.example/deal'),
        benefit: _benefit(type: BenefitRedemptionType.link),
        openerThrows: true,
      );
      await tester.tap(find.text('Åpne tilbudet'));
      await tester.pumpAndSettle();
      expect(
        find.text('Klarte ikke å åpne lenken. Prøv igjen.'),
        findsOneWidget,
      );

      api.pending = Completer<String>();
      await tester.tap(find.text('Prøv igjen'));
      await tester.tap(find.text('Prøv igjen'));
      await tester.pump();
      expect(api.revealed.length, 2);

      api.pending!.complete('https://partner.example/deal');
      await tester.pumpAndSettle();
      expect(api.revealed.length, 2);
    });

    testWidgets('closing and reopening the panel forgets the code', (
      tester,
    ) async {
      final shown = ValueNotifier(true);
      addTearDown(shown.dispose);
      final api = await _pump(tester, shown: shown);
      await tester.tap(find.text('Vis rabattkode'));
      await tester.pumpAndSettle();
      expect(find.text('CODE-1234'), findsOneWidget);

      shown.value = false;
      await tester.pumpAndSettle();
      expect(find.text('CODE-1234'), findsNothing);

      shown.value = true;
      await tester.pumpAndSettle();
      expect(find.text('CODE-1234'), findsNothing);
      expect(find.text('Vis rabattkode'), findsOneWidget);
      expect(api.revealed.length, 1);
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
        final api = await _pump(
          tester,
          api: _FakeApi(revealError: BenefitsApiException(kind)),
        );
        await tester.tap(find.text('Vis rabattkode'));
        await tester.pumpAndSettle();
        expect(find.text(_outage), findsOneWidget);
        expect(find.text('Bli medlem'), findsNothing);
        await tester.tap(find.text('Prøv igjen'));
        await tester.pumpAndSettle();
        expect(api.revealed.length, 2);
      });
    }

    testWidgets('reveal not_member shows the members-only panel', (
      tester,
    ) async {
      await _pump(
        tester,
        api: _FakeApi(
          revealError: const BenefitsApiException(
            BenefitsApiErrorKind.notMember,
          ),
        ),
      );
      await tester.tap(find.text('Vis rabattkode'));
      await tester.pumpAndSettle();
      expect(find.text(_locked), findsOneWidget);
      expect(find.text('Bli medlem'), findsOneWidget);
      expect(find.text('Vis rabattkode'), findsNothing);
    });

    for (final kind in [
      BenefitsApiErrorKind.notFound,
      BenefitsApiErrorKind.noCode,
    ]) {
      testWidgets('reveal $kind shows not found', (tester) async {
        await _pump(
          tester,
          api: _FakeApi(revealError: BenefitsApiException(kind)),
        );
        await tester.tap(find.text('Vis rabattkode'));
        await tester.pumpAndSettle();
        expect(find.text(_notFound), findsOneWidget);
      });
    }

    testWidgets('a link deal opens an https link', (tester) async {
      final opened = <Uri>[];
      await _pump(
        tester,
        api: _FakeApi(revealResult: 'https://partner.example/deal'),
        benefit: _benefit(type: BenefitRedemptionType.link),
        opened: opened,
      );
      await tester.tap(find.text('Åpne tilbudet'));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://partner.example/deal')]);
      expect(find.text('Åpne tilbudet'), findsOneWidget);
      expect(find.text('https://partner.example/deal'), findsNothing);
    });

    testWidgets('a link deal refuses a non-https link', (tester) async {
      final opened = <Uri>[];
      await _pump(
        tester,
        api: _FakeApi(revealResult: 'http://partner.example/deal'),
        benefit: _benefit(type: BenefitRedemptionType.link),
        opened: opened,
      );
      await tester.tap(find.text('Åpne tilbudet'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(find.text(_notFound), findsOneWidget);
    });

    testWidgets('a link that will not open says so, not "unavailable"', (
      tester,
    ) async {
      final api = await _pump(
        tester,
        api: _FakeApi(revealResult: 'https://partner.example/deal'),
        benefit: _benefit(type: BenefitRedemptionType.link),
        openerThrows: true,
      );
      await tester.tap(find.text('Åpne tilbudet'));
      await tester.pumpAndSettle();
      expect(
        find.text('Klarte ikke å åpne lenken. Prøv igjen.'),
        findsOneWidget,
      );
      expect(find.text(_outage), findsNothing);
      await tester.tap(find.text('Prøv igjen'));
      await tester.pumpAndSettle();
      expect(api.revealed.length, 2);
    });

    for (final next in [_reconnect, _loading]) {
      testWidgets('a revealed code stays when the pass goes ${next.status}', (
        tester,
      ) async {
        await _pump(tester);
        await tester.tap(find.text('Vis rabattkode'));
        await tester.pumpAndSettle();
        _pass!.show(next);
        await tester.pump();
        expect(find.text('CODE-1234'), findsOneWidget);
        expect(find.text(_outage), findsNothing);
      });
    }

    testWidgets('a revealed code goes when the pass says not a member', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('Vis rabattkode'));
      await tester.pumpAndSettle();
      _pass!.show(_noPass(NoPassState.notMember));
      await tester.pumpAndSettle();
      expect(find.text('CODE-1234'), findsNothing);
      expect(find.text(_locked), findsOneWidget);
    });
  });

  group('not a member', () {
    testWidgets('onsite: the locked panel with the count and campus', (
      tester,
    ) async {
      final api = await _pump(
        tester,
        benefit: _benefit(type: BenefitRedemptionType.onsite),
        pass: _noPass(NoPassState.notMember),
        otherCount: 26,
        campusName: 'Trondheim',
      );
      expect(find.text(_locked), findsOneWidget);
      expect(
        find.text(
          'Bli medlem for å bruke dette tilbudet og 26 andre fordeler i '
          'Trondheim.',
        ),
        findsOneWidget,
      );
      expect(find.text('Vis medlemskortet'), findsNothing);
      expect(api.revealed, isEmpty);
    });

    testWidgets('"Bli medlem" opens the membership page', (tester) async {
      final api = await _pump(tester, pass: _noPass(NoPassState.notMember));
      expect(find.text('Vis rabattkode'), findsNothing);
      await tester.tap(find.text('Bli medlem'));
      await tester.pumpAndSettle();
      expect(find.text('membership page'), findsOneWidget);
      expect(api.revealed, isEmpty);
    });

    testWidgets('no count yet: the locked text leaves the count out', (
      tester,
    ) async {
      await _pump(tester, pass: _noPass(NoPassState.notMember), otherCount: 0);
      expect(
        find.text('Bli medlem for å bruke dette tilbudet.'),
        findsOneWidget,
      );
    });

    for (final type in BenefitRedemptionType.values) {
      testWidgets('$type: the locked panel', (tester) async {
        await _pump(
          tester,
          benefit: _benefit(type: type),
          pass: _noPass(NoPassState.expired),
        );
        expect(find.text(_locked), findsOneWidget);
        expect(find.text('Bli medlem'), findsOneWidget);
      });
    }
  });

  group('signed out', () {
    for (final type in BenefitRedemptionType.values) {
      testWidgets('$type: the locked panel asks to sign in', (tester) async {
        await _pump(
          tester,
          benefit: _benefit(type: type),
          pass: _signedOut,
        );
        expect(find.text(_locked), findsOneWidget);
        expect(
          find.text('Logg inn for å bruke tilbudet som medlem.'),
          findsOneWidget,
        );
        expect(find.text('Logg inn'), findsOneWidget);
        expect(find.text('Bli medlem'), findsNothing);
      });
    }

    testWidgets('"Logg inn" goes to the login page', (tester) async {
      await _pump(tester, pass: _signedOut);
      await tester.tap(find.text('Logg inn'));
      await tester.pumpAndSettle();
      expect(find.text('login page'), findsOneWidget);
    });
  });

  group('upcoming', () {
    for (final type in BenefitRedemptionType.values) {
      testWidgets('$type: says when it starts, with no button', (tester) async {
        await _pump(
          tester,
          benefit: _benefit(type: type),
          pass: _noPass(NoPassState.notMember),
          overview: membershipOverviewOf(upcoming: [spring2027Semester]),
        );
        await tester.pump();
        expect(
          find.text(
            'Medlemskapet ditt starter 1. januar 2027. Da kan du bruke '
            'tilbudet.',
          ),
          findsOneWidget,
        );
        expect(find.byType(FilledButton), findsNothing);
        expect(find.text('Bli medlem'), findsNothing);
      });
    }
  });

  group('needs BI', () {
    for (final type in BenefitRedemptionType.values) {
      testWidgets('$type: the BI sign-in card', (tester) async {
        await _pump(
          tester,
          benefit: _benefit(type: type),
          pass: _noPass(NoPassState.noBiIdentity),
        );
        expect(find.text('Logg inn med BI-studentkontoen din'), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, 'Logg inn med BI'),
          findsOneWidget,
        );
        expect(find.text('Bli medlem'), findsNothing);
      });
    }

    testWidgets('"Logg inn med BI" runs the BI flow and reloads the pass', (
      tester,
    ) async {
      await _pump(tester, pass: _noPass(NoPassState.noBiIdentity));
      await tester.tap(find.widgetWithText(FilledButton, 'Logg inn med BI'));
      await tester.pump();
      await tester.pump();
      expect(_bi!.syncs, 1);
      expect(_overview!.refreshes, 1);
      expect(_pass!.retries, 1);
    });

    testWidgets('a double tap on "Logg inn med BI" starts one sync', (
      tester,
    ) async {
      await _pump(tester, pass: _noPass(NoPassState.noBiIdentity));
      final pending = _bi!.pending = Completer<BiSyncResult>();
      final button = find.widgetWithText(FilledButton, 'Logg inn med BI');
      await tester.tap(button);
      await tester.tap(button);
      await tester.pump();
      expect(_bi!.syncs, 1);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      pending.complete(const BiSyncResult(success: true, studentId: 's1'));
      await tester.pumpAndSettle();
      expect(_bi!.syncs, 1);
    });
  });

  group('checking', () {
    final labels = {
      BenefitRedemptionType.code: 'Vis rabattkode',
      BenefitRedemptionType.link: 'Åpne tilbudet',
      BenefitRedemptionType.onsite: 'Vis medlemskortet',
    };
    for (final MapEntry(key: type, value: label) in labels.entries) {
      testWidgets('$type: only a disabled pill with a spinner', (tester) async {
        final semantics = tester.ensureSemantics();
        final api = await _pump(
          tester,
          benefit: _benefit(type: type),
          pass: _loading,
        );
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(button.onPressed, isNull);
        expect(
          find.descendant(
            of: find.byType(FilledButton),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        // Neutral: no copy that reads as either answer.
        expect(_panelText, findsNothing);
        expect(find.text('Vis medlemskortet i kassen'), findsNothing);
        expect(
          find.text('Vis kortet før du betaler, så får du rabatten.'),
          findsNothing,
        );
        expect(find.text('Bli medlem'), findsNothing);
        expect(find.text(_locked), findsNothing);
        expect(find.text(_outage), findsNothing);
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(
            label: label,
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
          ),
        );
        expect(api.revealed, isEmpty);
        semantics.dispose();
      });
    }

    testWidgets('none: nothing', (tester) async {
      await _pump(
        tester,
        benefit: _benefit(type: BenefitRedemptionType.none),
        pass: _loading,
      );
      expect(_panelText, findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('check failed', () {
    for (final type in [
      BenefitRedemptionType.code,
      BenefitRedemptionType.link,
      BenefitRedemptionType.onsite,
    ]) {
      testWidgets('$type: the outage line, never "Bli medlem"', (tester) async {
        await _pump(
          tester,
          benefit: _benefit(type: type),
          pass: _noPass(NoPassState.unavailable),
        );
        expect(find.text(_outage), findsOneWidget);
        expect(find.text('Prøv igjen'), findsOneWidget);
        expect(find.text('Bli medlem'), findsNothing);
        expect(find.text(_locked), findsNothing);
      });
    }

    testWidgets('none: nothing', (tester) async {
      await _pump(
        tester,
        benefit: _benefit(type: BenefitRedemptionType.none),
        pass: _reconnect,
      );
      expect(_panelText, findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('the outage retry asks the pass to retry', (tester) async {
      await _pump(tester, pass: _noPass(NoPassState.unavailable));
      await tester.tap(find.text('Prøv igjen'));
      await tester.pump();
      expect(_pass!.retries, 1);
    });
  });

  group('large text and dark mode', () {
    for (final brightness in Brightness.values) {
      testWidgets('$brightness at text scale 2: no overflow', (tester) async {
        final shows = <MemberPassView, String>{
          _active: 'Vis rabattkode',
          _noPass(NoPassState.notMember): _locked,
          _noPass(NoPassState.noBiIdentity): 'Logg inn med BI',
          _noPass(NoPassState.unavailable): _outage,
        };
        for (final MapEntry(key: view, value: shown) in shows.entries) {
          await _pump(
            tester,
            benefit: _benefit(website: 'https://kaffebrenneriet.no'),
            pass: view,
            brightness: brightness,
            textScale: 2,
          );
          expect(find.text(shown), findsOneWidget);
          expect(tester.takeException(), isNull, reason: shown);
          await tester.pumpWidget(const SizedBox());
        }
        await _pump(
          tester,
          benefit: _benefit(website: 'https://kaffebrenneriet.no'),
          brightness: brightness,
          textScale: 2,
        );
        await tester.tap(find.text('Vis rabattkode'));
        await tester.pumpAndSettle();
        expect(find.text('Til butikken'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'code');
      });
    }
  });

  group('standing from the pass', () {
    // (pass view, Bli medlem, outage line, Logg inn, BI card, reveal pill)
    final cases = <String, (MemberPassView, bool, bool, bool, bool, bool)>{
      'reconnect': (_reconnect, false, true, false, false, false),
      'loading': (_loading, false, false, false, false, false),
      'noPass(null)': (
        const MemberPassView(status: PassStatus.noPass),
        false,
        true,
        false,
        false,
        false,
      ),
      'noPass(unavailable)': (
        _noPass(NoPassState.unavailable),
        false,
        true,
        false,
        false,
        false,
      ),
      'signedOut': (_signedOut, false, false, true, false, false),
      'expired': (
        _noPass(NoPassState.expired),
        true,
        false,
        false,
        false,
        false,
      ),
      'noBiIdentity': (
        _noPass(NoPassState.noBiIdentity),
        false,
        false,
        false,
        true,
        false,
      ),
      'notMember': (
        _noPass(NoPassState.notMember),
        true,
        false,
        false,
        false,
        false,
      ),
      'active': (_active, false, false, false, false, true),
    };
    for (final entry in cases.entries) {
      testWidgets(entry.key, (tester) async {
        final (view, member, outage, signIn, bi, reveal) = entry.value;
        final api = await _pump(tester, pass: view);
        expect(find.text('Bli medlem'), member ? findsOneWidget : findsNothing);
        expect(find.text(_outage), outage ? findsOneWidget : findsNothing);
        expect(find.text('Logg inn'), signIn ? findsOneWidget : findsNothing);
        expect(
          find.text('Logg inn med BI'),
          bi ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Vis rabattkode'),
          reveal ? findsOneWidget : findsNothing,
        );
        expect(api.revealed, isEmpty);
      });
    }
  });
}
