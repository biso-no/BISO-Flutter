import 'dart:async';

import 'package:biso/data/models/campus_benefit.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/models/member_pass.dart';
import 'package:biso/data/models/membership_overview.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/benefits_api_client.dart';
import 'package:biso/presentation/screens/benefits/benefits_screen.dart';
import 'package:biso/presentation/widgets/benefits/benefits_top_card.dart';
import 'package:biso/presentation/widgets/biso/biso.dart'
    show BisoEmptyState, BisoErrorState, BisoSkeleton;
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/benefits/benefits_providers.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/member_pass/member_pass_provider.dart';
import 'package:biso/providers/member_pass/member_pass_session.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/biso_screen_harness.dart';
import '../../../helpers/fake_member_pass_api.dart'
    show FakeScreenPresentation, activeView;

class _FakeApi implements BenefitsApi {
  _FakeApi({List<CampusBenefit>? benefits}) : benefits = benefits ?? _all;

  List<CampusBenefit> benefits;

  /// Thrown by the next fetches while set.
  BenefitsApiException? error;

  /// When set, fetches wait for it.
  Completer<List<CampusBenefit>>? pending;
  final campuses = <String?>[];

  @override
  Future<List<CampusBenefit>> fetchBenefits({String? campusId}) async {
    campuses.add(campusId);
    final wait = pending;
    if (wait != null) return wait.future;
    final fail = error;
    if (fail != null) throw fail;
    return benefits;
  }

  @override
  Future<String> reveal(String benefitId) async => 'CODE-1234';
}

/// Shows [initial] until a test calls [show].
class _FakePass extends MemberPassNotifier {
  _FakePass(this.initial);
  final MemberPassView initial;

  @override
  MemberPassView build() => initial;

  void show(MemberPassView view) => state = view;
}

class _Overview extends MembershipOverviewNotifier {
  @override
  Future<MembershipOverview?> build() async => null;

  @override
  Future<void> refresh({bool force = true}) async {}
}

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The Home campus. Counts every write, which the screen must never make.
class _FilterCampus extends StateNotifier<CampusState>
    implements FilterCampusNotifier {
  _FilterCampus(CampusModel campus)
    : super(CampusState(campus: campus, isInitialized: true));

  int writes = 0;

  @override
  Future<void> selectFilterCampus(CampusModel campus) async {
    writes++;
    state = state.copyWith(campus: campus);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CampusModel _campus(String id, String name) => CampusModel(
  id: id,
  name: name,
  description: '',
  location: name,
  imageUrl: '',
  heroImageUrl: '',
  stats: const CampusStats(),
);

const _user = UserModel(
  id: 'u1',
  name: 'Kari',
  email: 'kari@bi.no',
  campusId: '3',
);

const _signedInState = AuthState(
  isAuthenticated: true,
  user: _user,
  hasProfile: true,
  isProfileComplete: true,
);

CampusBenefit _deal(
  String id,
  String title, {
  String? category,
  bool featured = false,
}) => CampusBenefit(
  id: id,
  campusId: '3',
  section: BenefitSection.member,
  category: category,
  title: BenefitText(nb: title),
  redemptionType: BenefitRedemptionType.onsite,
  isFeatured: featured,
);

const _perk = CampusBenefit(
  id: 'p1',
  campusId: '3',
  section: BenefitSection.career,
  title: BenefitText(nb: 'CV-portrett'),
  redemptionType: BenefitRedemptionType.none,
);

/// Six deals in three categories, one picked by BISO, and one perk.
final _all = [
  _deal('d1', 'Graffi Grill', category: 'food_drink', featured: true),
  _deal('d2', 'Club Tempo', category: 'nightlife'),
  _deal('d3', 'GoBowl', category: 'health_fitness'),
  _deal('d4', 'Egon Solsiden', category: 'food_drink'),
  _deal('d5', 'RUSH Trampolinepark', category: 'health_fitness'),
  _deal('d6', 'Barbequez', category: 'food_drink'),
  _perk,
];

MemberPassView _noPass(NoPassState s) =>
    MemberPassView(status: PassStatus.noPass, noPassState: s);

final _notMember = _noPass(NoPassState.notMember);
const _signedOut = MemberPassView(status: PassStatus.signedOut);
const _loading = MemberPassView(status: PassStatus.loading);
const _reconnect = MemberPassView(status: PassStatus.reconnect);

const _join = 'Bli medlem';
const _signIn = 'Logg inn';
const _youAreMember = 'Du er medlem';
const _stickyTitle = 'Alt dette får du som medlem';
const _empty = 'Ingen fordeler her ennå.';

/// The screen is taller than a phone, so every section is built.
const _tall = Size(390, 2400);

_FakePass? _pass;
_FilterCampus? _filter;

Future<_FakeApi> _pump(
  WidgetTester tester, {
  _FakeApi? api,
  String? campusParam,
  MemberPassView? pass,
  AuthState auth = _signedInState,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  Size size = const Size(390, 844),
}) async {
  final fake = api ?? _FakeApi();
  await pumpBisoScreen(
    tester,
    BenefitsScreen(campusParam: campusParam),
    routed: true,
    locale: const Locale('no'),
    brightness: brightness,
    textScale: textScale,
    size: size,
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
        path: '/explore/benefits/:benefitId',
        builder: (_, state) =>
            Scaffold(body: Text('deal ${state.pathParameters['benefitId']}')),
      ),
    ],
    overrides: [
      benefitsApiProvider.overrideWithValue(fake),
      memberPassProvider.overrideWith(
        () => _pass = _FakePass(pass ?? activeView()),
      ),
      membershipOverviewProvider.overrideWith(_Overview.new),
      authStateProvider.overrideWith((_) => _Auth(auth)),
      filterCampusStateProvider.overrideWith(
        (_) => _filter = _FilterCampus(_campus('3', 'Trondheim')),
      ),
      switcherCampusesProvider.overrideWith(
        (_) async => [_campus('1', 'Oslo'), _campus('3', 'Trondheim')],
      ),
      benefitClockProvider.overrideWithValue(
        () => DateTime.utc(2026, 11, 10, 12),
      ),
      screenPresentationProvider.overrideWithValue(FakeScreenPresentation()),
    ],
  );
  // The list and the membership overview settle a frame later.
  await tester.pump();
  await tester.pump();
  return fake;
}

/// Scrolls the top card well above the header and lets the bar settle.
/// Large text makes the card taller, so it takes a longer drag.
Future<void> _scrollPastTopCard(WidgetTester tester, {double by = 900}) async {
  await tester.drag(find.byType(CustomScrollView), Offset(0, -by));
  await tester.pumpAndSettle();
}

Finder _inBar(Finder finder) =>
    find.descendant(of: find.byKey(benefitsStickyBarKey), matching: finder);

void main() {
  testWidgets('lays out the campus line, top card and the three sections', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final api = await _pump(tester, size: _tall);

    expect(api.campuses, ['3']);
    expect(find.text('Fordeler'), findsWidgets);
    expect(find.text('Trondheim'), findsOneWidget);
    expect(find.byType(BenefitsTopCard), findsOneWidget);
    expect(find.text('Utvalgt'), findsOneWidget);
    expect(find.text('Alle tilbud'), findsOneWidget);
    // Six deals; the perk is not one of them.
    expect(find.text('6'), findsOneWidget);
    expect(find.text('Mer enn rabatter'), findsOneWidget);
    expect(find.text('CV-portrett'), findsOneWidget);
    expect(
      tester.getSemantics(
        find.bySemanticsLabel('For BISO-medlemmer i Trondheim'),
      ),
      isSemantics(isButton: true, hasTapAction: true, hint: 'Velg campus'),
    );
    semantics.dispose();
  });

  testWidgets('member sees the member row and no sticky bar after scrolling', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text(_youAreMember), findsOneWidget);
    expect(find.text(_join), findsNothing);

    await _scrollPastTopCard(tester);
    expect(find.text(_stickyTitle), findsNothing);
    expect(find.byKey(benefitsStickyBarKey), findsNothing);
  });

  testWidgets(
    'non-member: no sticky bar at the top, sticky bar after scrolling past '
    'the top card',
    (tester) async {
      await _pump(tester, pass: _notMember);
      expect(find.text(_join), findsOneWidget);
      expect(find.text(_stickyTitle), findsNothing);

      await _scrollPastTopCard(tester);
      expect(find.text(_stickyTitle), findsOneWidget);
      // Every benefit on the screen, the perk too.
      expect(_inBar(find.text('7 fordeler i Trondheim')), findsOneWidget);
      expect(_inBar(find.text(_join)), findsOneWidget);

      // Back at the top the card's own button is enough.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 900));
      await tester.pumpAndSettle();
      expect(find.text(_stickyTitle), findsNothing);

      await _scrollPastTopCard(tester);
      await tester.tap(_inBar(find.text(_join)));
      await tester.pumpAndSettle();
      expect(find.text('membership page'), findsOneWidget);
    },
  );

  testWidgets('signed out: "Logg inn" in the card and the sticky bar', (
    tester,
  ) async {
    await _pump(tester, pass: _signedOut, auth: const AuthState());
    expect(find.text(_signIn), findsOneWidget);
    expect(find.text(_join), findsNothing);

    await _scrollPastTopCard(tester);
    expect(_inBar(find.text(_signIn)), findsOneWidget);
    expect(find.text(_join), findsNothing);

    await tester.tap(_inBar(find.text(_signIn)));
    await tester.pumpAndSettle();
    expect(find.text('login page'), findsOneWidget);
  });

  testWidgets('checking then member never shows "Bli medlem"', (tester) async {
    // Off screen too: the top card stays built after it scrolls away.
    final join = find.text(_join, skipOffstage: false);
    await _pump(tester, pass: _loading);
    expect(join, findsNothing);
    expect(find.text(_signIn, skipOffstage: false), findsNothing);

    await _scrollPastTopCard(tester);
    expect(join, findsNothing);
    expect(find.text(_stickyTitle), findsNothing);

    _pass!.show(activeView());
    await tester.pump();
    expect(find.text(_youAreMember, skipOffstage: false), findsOneWidget);
    expect(join, findsNothing);
    expect(find.text(_stickyTitle), findsNothing);

    await tester.pumpAndSettle();
    expect(join, findsNothing);
    expect(find.text(_stickyTitle), findsNothing);
  });

  testWidgets(
    'a failed check or a BI link to make never shows the sticky bar',
    (tester) async {
      for (final pass in [_reconnect, _noPass(NoPassState.noBiIdentity)]) {
        await _pump(tester, pass: pass);
        await _scrollPastTopCard(tester);
        expect(find.text(_stickyTitle), findsNothing, reason: '${pass.status}');
        expect(find.text(_join), findsNothing, reason: '${pass.status}');
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets('no Utvalgt: the section is gone', (tester) async {
    await _pump(
      tester,
      size: _tall,
      api: _FakeApi(
        benefits: [
          _deal('d2', 'Club Tempo', category: 'nightlife'),
          _deal('d4', 'Egon Solsiden', category: 'food_drink'),
        ],
      ),
    );
    expect(find.text('Utvalgt'), findsNothing);
    expect(find.text('Alle tilbud'), findsOneWidget);
    expect(find.text('Club Tempo'), findsOneWidget);
  });

  testWidgets('chip filter narrows the grid', (tester) async {
    await _pump(tester, size: _tall);
    expect(find.text('Club Tempo'), findsOneWidget);
    expect(find.text('Egon Solsiden'), findsOneWidget);

    await tester.tap(find.text('Mat og drikke'));
    await tester.pump();
    expect(find.text('Egon Solsiden'), findsOneWidget);
    expect(find.text('Barbequez'), findsOneWidget);
    expect(find.text('Club Tempo'), findsNothing);
    expect(find.text('GoBowl'), findsNothing);
    // The section still counts every deal.
    expect(find.text('6'), findsOneWidget);

    await tester.tap(find.text('Alle'));
    await tester.pump();
    expect(find.text('Club Tempo'), findsOneWidget);
  });

  testWidgets(
    'campusParam "national" lists all-of-BISO benefits and labels "Hele BISO"',
    (tester) async {
      final api = await _pump(tester, campusParam: 'national');
      expect(api.campuses, [null]);
      expect(find.text('Hele BISO'), findsOneWidget);
    },
  );

  testWidgets('a campus id starts on that campus, not the Home campus', (
    tester,
  ) async {
    final api = await _pump(tester, campusParam: '1');
    await tester.pump();
    expect(api.campuses, ['1']);
    expect(find.text('Oslo'), findsOneWidget);
  });

  testWidgets('switching campus refetches for the new campus and leaves '
      'filterCampusProvider alone', (tester) async {
    final api = await _pump(tester);
    expect(api.campuses, ['3']);

    await tester.tap(find.text('Trondheim'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oslo'));
    await tester.pumpAndSettle();

    expect(api.campuses, ['3', '1']);
    expect(find.text('Oslo'), findsOneWidget);
    expect(find.text('Trondheim'), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(BenefitsScreen)),
    );
    expect(container.read(filterCampusProvider).id, '3');
    expect(_filter!.writes, 0);
  });

  testWidgets('switching campus resets the category filter to "Alle"', (
    tester,
  ) async {
    await _pump(tester, size: _tall);
    await tester.tap(find.text('Mat og drikke'));
    await tester.pump();
    expect(find.text('Club Tempo'), findsNothing);

    await tester.tap(find.text('Trondheim'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oslo'));
    await tester.pumpAndSettle();

    expect(find.text('Club Tempo'), findsOneWidget);
    expect(find.text('GoBowl'), findsOneWidget);
  });

  testWidgets('loading, error and retry', (tester) async {
    final api = _FakeApi()..pending = Completer();
    await _pump(tester, api: api);
    expect(find.byType(BisoSkeleton), findsWidgets);
    expect(find.text('Trondheim'), findsOneWidget);
    expect(find.byType(BenefitsTopCard), findsNothing);

    api.pending!.completeError(
      const BenefitsApiException(BenefitsApiErrorKind.network),
    );
    api.pending = null;
    await tester.pump();
    await tester.pump();
    expect(find.byType(BisoErrorState), findsOneWidget);
    expect(find.byType(BisoSkeleton), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(BisoErrorState),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(api.campuses, ['3', '3']);
    expect(find.byType(BisoErrorState), findsNothing);
    expect(find.byType(BenefitsTopCard), findsOneWidget);
  });

  testWidgets('empty campus shows the empty state with the campus line', (
    tester,
  ) async {
    await _pump(tester, api: _FakeApi(benefits: const []));
    expect(find.text(_empty), findsOneWidget);
    expect(find.byType(BisoEmptyState), findsOneWidget);
    expect(find.byType(BenefitsTopCard), findsNothing);

    // The student can still switch to a campus with benefits.
    await tester.tap(find.text('Trondheim'));
    await tester.pumpAndSettle();
    expect(find.text('Oslo'), findsOneWidget);
  });

  testWidgets('notDeployed shows the empty state', (tester) async {
    final api = _FakeApi()
      ..error = const BenefitsApiException(BenefitsApiErrorKind.notDeployed);
    await _pump(tester, api: api, pass: _notMember);
    expect(find.text(_empty), findsOneWidget);
    expect(find.byType(BisoErrorState), findsNothing);
    expect(find.text('Trondheim'), findsOneWidget);
    expect(find.text(_join), findsNothing);
  });

  testWidgets('no deals but some perks: the top card and the perks only', (
    tester,
  ) async {
    await _pump(tester, api: _FakeApi(benefits: const [_perk]));
    expect(find.byType(BenefitsTopCard), findsOneWidget);
    expect(find.text('Alle tilbud'), findsNothing);
    expect(find.text('Utvalgt'), findsNothing);
    expect(find.text('Mer enn rabatter'), findsOneWidget);
  });

  testWidgets('reduced motion: the sticky bar appears without sliding', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pump(tester, pass: _notMember);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pump();
    await tester.pump();
    final first = tester.getRect(find.byKey(benefitsStickyBarKey));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(benefitsStickyBarKey)), first);
  });

  testWidgets('dark mode and text scale 2.0 pump without exceptions', (
    tester,
  ) async {
    final long = _FakeApi(
      benefits: [
        // 70 characters.
        _deal(
          'd1',
          'Graffi Grill på Solsiden med studentmeny hele uka og gratis brus i dag',
          category: 'food_drink',
          featured: true,
        ),
        ..._all.skip(1),
      ],
    );
    for (final brightness in Brightness.values) {
      for (final textScale in [1.0, 2.0]) {
        await _pump(
          tester,
          api: long,
          pass: _notMember,
          brightness: brightness,
          textScale: textScale,
        );
        expect(tester.takeException(), isNull);
        await _scrollPastTopCard(tester, by: 900 * textScale);
        expect(
          find.text(_stickyTitle),
          findsOneWidget,
          reason: '$brightness at text scale $textScale',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '$brightness at text scale $textScale',
        );
        await tester.pumpWidget(const SizedBox());
      }
    }
  });
}
