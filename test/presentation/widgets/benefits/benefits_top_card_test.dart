import 'dart:async';

import 'package:biso/core/theme/biso_page.dart';
import 'package:biso/data/models/campus_benefit.dart';
import 'package:biso/data/models/member_pass.dart';
import 'package:biso/data/models/membership_overview.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/bi_sign_in_service.dart';
import 'package:biso/data/services/bi_sync_api_client.dart';
import 'package:biso/presentation/screens/profile/member_pass_presentation.dart';
import 'package:biso/presentation/widgets/benefits/benefits_top_card.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/auth/bi_sign_in_provider.dart';
import 'package:biso/providers/benefits/benefit_showcase.dart';
import 'package:biso/providers/member_pass/member_pass_provider.dart';
import 'package:biso/providers/member_pass/member_pass_session.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/biso_screen_harness.dart';
import '../../../helpers/fake_member_pass_api.dart'
    show FakeScreenPresentation, activeView;
import '../../../helpers/membership_fixtures.dart';

class _FakePass extends MemberPassNotifier {
  _FakePass(this.view);
  final MemberPassView view;
  int retries = 0;

  /// [view] for [_user]. Another account restarts the pass in loading, as
  /// the real one does.
  @override
  MemberPassView build() =>
      ref.watch(membershipUserIdProvider) == _user.id ? view : _loading;

  @override
  Future<void> retry() async => retries++;
}

class _Overview extends MembershipOverviewNotifier {
  _Overview(this.value);

  final MembershipOverview? value;

  @override
  Future<MembershipOverview?> build() async => value;

  @override
  Future<void> refresh({bool force = true}) async {}
}

/// Answers the BI sync with [answer], or waits for [pending] when set.
class _FakeBiSignIn extends BiSignInService {
  BiSyncResult answer = const BiSyncResult(success: true, studentId: 's1');
  Completer<BiSyncResult>? pending;
  int syncs = 0;

  @override
  Future<BiSyncResult> syncOnly() async {
    syncs++;
    final wait = pending;
    if (wait != null) return wait.future;
    return answer;
  }
}

/// Signed in as [_user]. A BI sign-in switches to [signedInState] when set,
/// then waits for [gate] before it answers, as the real one waits on BI.
class _Auth extends Notifier<AuthState> implements AuthNotifier {
  final AuthState _initial;

  @override
  AuthState build() => _initial;

  _Auth()
    : _initial = const AuthState(
          isAuthenticated: true,
          user: _user,
          hasProfile: true,
          isProfileComplete: true,
        );

  BiSignInOutcome biOutcome = const BiSignInFailed(BiSignInFailure.failed);
  AuthState? signedInState;
  Completer<void>? gate;

  @override
  Future<BiSignInOutcome> signInWithBi() async {
    final next = signedInState;
    if (next != null) state = next;
    await gate?.future;
    return biOutcome;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _user = UserModel(
  id: 'u1',
  name: 'Kari',
  email: 'kari@bi.no',
  campusId: '3',
);

_FakeBiSignIn? _bi;
_Auth? _auth;

MemberPassView _noPass(NoPassState s) =>
    MemberPassView(status: PassStatus.noPass, noPassState: s);

const _signedOut = MemberPassView(status: PassStatus.signedOut);
const _loading = MemberPassView(status: PassStatus.loading);
const _reconnect = MemberPassView(status: PassStatus.reconnect);

CampusBenefit _deal(String id, {String? image}) => CampusBenefit(
  id: id,
  campusId: '3',
  section: BenefitSection.member,
  title: BenefitText(nb: 'Tilbud $id'),
  imageUrl: image,
  redemptionType: BenefitRedemptionType.onsite,
);

/// [deals] member deals, the first [images] of them with a picture, and one
/// career perk.
BenefitShowcase _showcase({int deals = 3, int images = 0}) =>
    BenefitShowcase.from([
      for (var i = 0; i < deals; i++)
        _deal('d$i', image: i < images ? 'https://img.test/$i.png' : null),
      const CampusBenefit(
        id: 'p1',
        campusId: '3',
        section: BenefitSection.career,
        title: BenefitText(nb: 'CV-portrett'),
        redemptionType: BenefitRedemptionType.none,
      ),
    ], now: DateTime.utc(2026, 11, 10, 12));

Future<void> _pump(
  WidgetTester tester, {
  MemberPassView? pass,
  MembershipOverview? overview,
  BenefitShowcase? showcase,
  String campusName = 'Trondheim',
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) async {
  await pumpBisoScreen(
    tester,
    BisoPage(
      title: 'Fordeler',
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverToBoxAdapter(
            child: BenefitsTopCard(
              showcase: showcase ?? _showcase(),
              campusName: campusName,
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
      GoRoute(
        path: '/onboarding',
        builder: (_, _) => const Scaffold(body: Text('onboarding page')),
      ),
    ],
    overrides: [
      memberPassProvider.overrideWith(() => _FakePass(pass ?? activeView())),
      membershipOverviewProvider.overrideWith(() => _Overview(overview)),
      authStateProvider.overrideWith(() => _auth = _Auth()),
      biSignInServiceProvider.overrideWithValue(_bi = _FakeBiSignIn()),
      screenPresentationProvider.overrideWithValue(FakeScreenPresentation()),
    ],
  );
  // The membership overview settles a frame later.
  await tester.pump();
}

const _join = 'Bli medlem';
const _signIn = 'Logg inn';
const _youAreMember = 'Du er medlem';
const _showCard = 'Vis kort';
const _startsOn = 'Medlemskapet ditt starter 1. januar 2027.';
const _needsBiTitle = 'Logg inn med BI-studentkontoen din';
const _needsBiCta = 'Logg inn med BI';

final _upcoming = membershipOverviewOf(upcoming: [spring2027Semester]);

/// Every standing, as the pass and the overview give it.
final _standings = <String, (MemberPassView, MembershipOverview?)>{
  'member': (activeView(), null),
  'upcoming': (_noPass(NoPassState.notMember), _upcoming),
  'needsBi': (_noPass(NoPassState.noBiIdentity), null),
  'notMember': (_noPass(NoPassState.notMember), null),
  'signedOut': (_signedOut, null),
  'checking': (_loading, null),
  'unavailable': (_reconnect, null),
};

void main() {
  group('count and text', () {
    testWidgets('a non-member sees the count and what waits for them', (
      tester,
    ) async {
      await _pump(tester, pass: _noPass(NoPassState.notMember));
      // Three deals and one perk.
      expect(find.text('4'), findsOneWidget);
      expect(
        find.text('fordeler venter på deg som BISO-medlem i Trondheim'),
        findsOneWidget,
      );
    });

    testWidgets('a member sees that the benefits are theirs', (tester) async {
      await _pump(tester);
      expect(find.text('fordeler er dine i Trondheim'), findsOneWidget);
    });

    testWidgets('an upcoming member sees the member text', (tester) async {
      await _pump(
        tester,
        pass: _noPass(NoPassState.notMember),
        overview: _upcoming,
      );
      expect(find.text('fordeler er dine i Trondheim'), findsOneWidget);
    });

    for (final name in ['needsBi', 'checking', 'unavailable']) {
      testWidgets('$name sees the neutral text', (tester) async {
        final (pass, overview) = _standings[name]!;
        await _pump(tester, pass: pass, overview: overview);
        expect(
          find.text('fordeler for BISO-medlemmer i Trondheim'),
          findsOneWidget,
        );
        expect(find.textContaining('venter på deg'), findsNothing);
        expect(find.textContaining('er dine'), findsNothing);
      });
    }

    testWidgets('all of BISO is named "Hele BISO"', (tester) async {
      await _pump(tester, campusName: '');
      expect(find.text('fordeler er dine i Hele BISO'), findsOneWidget);
    });
  });

  group('the action row', () {
    testWidgets('notMember: a "Bli medlem" pill opens the membership page', (
      tester,
    ) async {
      await _pump(tester, pass: _noPass(NoPassState.notMember));
      expect(find.text(_join), findsOneWidget);
      expect(find.text(_signIn), findsNothing);
      expect(find.text(_youAreMember), findsNothing);
      await tester.tap(find.text(_join));
      await tester.pumpAndSettle();
      expect(find.text('membership page'), findsOneWidget);
    });

    testWidgets('signedOut: a "Logg inn" pill goes to login', (tester) async {
      await _pump(tester, pass: _signedOut);
      expect(find.text(_signIn), findsOneWidget);
      expect(find.text(_join), findsNothing);
      expect(find.text(_youAreMember), findsNothing);
      await tester.tap(find.text(_signIn));
      await tester.pumpAndSettle();
      expect(find.text('login page'), findsOneWidget);
    });

    testWidgets('member: the seal row with the date and "Vis kort"', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text(_youAreMember), findsOneWidget);
      expect(find.text('Gyldig til 31. desember 2026'), findsOneWidget);
      expect(find.text(_showCard), findsOneWidget);
      expect(find.text(_join), findsNothing);
      expect(find.text(_signIn), findsNothing);
      await tester.tap(find.text(_showCard));
      // The pass keeps ticking, so it never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(MemberPassPresentation), findsOneWidget);
    });

    testWidgets('upcoming: when it starts, and no button', (tester) async {
      await _pump(
        tester,
        pass: _noPass(NoPassState.notMember),
        overview: _upcoming,
      );
      expect(find.text(_startsOn), findsOneWidget);
      expect(find.text(_showCard), findsNothing);
      expect(find.text(_join), findsNothing);
      expect(find.text(_signIn), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('needsBi: the BI row runs the BI flow', (tester) async {
      await _pump(tester, pass: _noPass(NoPassState.noBiIdentity));
      expect(find.text(_needsBiTitle), findsOneWidget);
      expect(find.text(_needsBiCta), findsOneWidget);
      expect(find.text(_join), findsNothing);
      expect(find.text(_youAreMember), findsNothing);
      await tester.tap(find.text(_needsBiCta));
      await tester.pump();
      await tester.pump();
      expect(_bi!.syncs, 1);
    });

    testWidgets('needsBi: a BI sign-in into a new account still finishes the '
        'flow while the pass reloads', (tester) async {
      await _pump(tester, pass: _noPass(NoPassState.noBiIdentity));
      final release = Completer<void>();
      _bi!.answer = const BiSyncResult.failed(BiSyncError.noBiIdentity);
      // Builds the lazy auth notifier, so [_auth] can be set up.
      ProviderScope.containerOf(
        tester.element(find.byType(BenefitsTopCard)),
      ).read(authStateProvider);
      _auth!
        ..biOutcome = const BiSignedIn(
          BiSyncResult(success: true, studentId: 's1'),
        )
        ..signedInState = const AuthState(
          isAuthenticated: true,
          user: UserModel(id: 'u2', name: 'Kari BI', email: 's1@bi.no'),
        )
        ..gate = release;

      await tester.tap(find.text(_needsBiCta));
      await tester.pump();
      await tester.pump();
      // The new account's pass is loading: the card is neutral meanwhile.
      expect(find.text(_needsBiTitle), findsNothing);
      expect(
        find.text('fordeler for BISO-medlemmer i Trondheim'),
        findsOneWidget,
      );

      release.complete();
      await tester.pumpAndSettle();
      // The account has no profile yet, so the flow ends in onboarding.
      expect(find.text('onboarding page'), findsOneWidget);
    });

    testWidgets('needsBi: a double tap starts one sync', (tester) async {
      await _pump(tester, pass: _noPass(NoPassState.noBiIdentity));
      final pending = _bi!.pending = Completer<BiSyncResult>();
      await tester.tap(find.text(_needsBiCta));
      await tester.tap(find.text(_needsBiCta));
      await tester.pump();
      expect(_bi!.syncs, 1);
      final pill = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text(_needsBiCta),
          matching: find.byType(FilledButton),
        ),
      );
      expect(pill.onPressed, isNull);

      pending.complete(const BiSyncResult(success: true, studentId: 's1'));
      await tester.pumpAndSettle();
      expect(_bi!.syncs, 1);
    });

    for (final name in ['checking', 'unavailable']) {
      testWidgets('$name: no pill and no member row', (tester) async {
        final (pass, overview) = _standings[name]!;
        await _pump(tester, pass: pass, overview: overview);
        expect(find.text(_join), findsNothing);
        expect(find.text(_signIn), findsNothing);
        expect(find.text(_youAreMember), findsNothing);
        expect(find.text(_needsBiCta), findsNothing);
        expect(find.byType(FilledButton), findsNothing);
      });
    }
  });

  group('partner images', () {
    testWidgets('no images: the row is left out', (tester) async {
      await _pump(tester, showcase: _showcase());
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.textContaining('+ '), findsNothing);
    });

    testWidgets('five images: all five, and no "+ N til"', (tester) async {
      await _pump(tester, showcase: _showcase(deals: 5, images: 5));
      expect(find.byType(CachedNetworkImage), findsNWidgets(5));
      expect(find.textContaining('+ '), findsNothing);
    });

    testWidgets('eight images: five, then "+ 3 til"', (tester) async {
      await _pump(tester, showcase: _showcase(deals: 8, images: 8));
      expect(find.byType(CachedNetworkImage), findsNWidgets(5));
      expect(find.text('+ 3 til'), findsOneWidget);
    });
  });

  for (final brightness in Brightness.values) {
    for (final MapEntry(key: name, value: (pass, overview))
        in _standings.entries) {
      testWidgets('$name in $brightness at text scale 2.0: no overflow', (
        tester,
      ) async {
        await _pump(
          tester,
          pass: pass,
          overview: overview,
          showcase: _showcase(deals: 8, images: 8),
          campusName: 'Trondheim og omegn',
          brightness: brightness,
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('dark mode pumps without exceptions', (tester) async {
    for (final MapEntry(value: (pass, overview)) in _standings.entries) {
      await _pump(
        tester,
        pass: pass,
        overview: overview,
        showcase: _showcase(deals: 6, images: 6),
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
