import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/models/member_pass.dart';
import 'package:biso/data/models/membership_overview.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/screens/profile/member_pass_presentation.dart';
import 'package:biso/presentation/screens/profile/member_pass_screen.dart';
import 'package:biso/presentation/screens/profile/membership_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/presentation/widgets/member_pass/member_pass_row.dart';
import 'package:biso/presentation/widgets/member_pass/pass_card.dart';
import 'package:biso/providers/member_pass/member_pass_provider.dart';
import 'package:biso/providers/member_pass/member_pass_session.dart';
import 'package:biso/providers/membership/membership_checkout_provider.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/biso_screen_harness.dart';
import '../../../helpers/fake_member_pass_api.dart';

class _Overview extends MembershipOverviewNotifier {
  bool linkNoted = false;

  @override
  Future<MembershipOverview?> build() async => null;

  @override
  void noteLinkStarted() => linkNoted = true;
}

MemberPassView _noPass(NoPassState state) =>
    MemberPassView(status: PassStatus.noPass, noPassState: state);

void main() {
  late FixedMemberPass pass;
  late _Overview overview;
  late List<Uri> launched;

  List<Override> overrides(MemberPassView view) {
    launched = [];
    return [
      // `expectBuildsCleanly` pumps the same override list several times
      // (once per brightness/text-scale combination), each on a fresh
      // ProviderScope. A Notifier's `overrideWith` factory must build a new
      // instance per container — Riverpod binds each Notifier to its owning
      // element exactly once — so `pass`/`overview` are (re)captured from
      // the factory itself rather than a value created ahead of time.
      memberPassProvider.overrideWith(() => pass = FixedMemberPass(view)),
      membershipOverviewProvider.overrideWith(() => overview = _Overview()),
      membershipUrlLauncherProvider.overrideWithValue((uri) async {
        launched.add(uri);
        return true;
      }),
      screenPresentationProvider.overrideWithValue(FakeScreenPresentation()),
      canAddApplePassesProvider.overrideWith((ref) async => false),
    ];
  }

  Future<GoRouter> pumpRouted(WidgetTester tester, MemberPassView view) async {
    final router = GoRouter(
      initialLocation: '/profile/member-pass',
      routes: [
        GoRoute(
          path: '/profile/member-pass',
          builder: (_, _) => const MemberPassScreen(),
        ),
        GoRoute(
          path: '/profile/membership',
          builder: (_, _) => const Scaffold(body: Text('Membership screen')),
        ),
        GoRoute(
          path: '/auth/login',
          builder: (_, _) => const Scaffold(body: Text('Login screen')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(view),
        child: MaterialApp.router(
          theme: PremiumTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    return router;
  }

  testWidgets('builds cleanly in every appearance', (tester) async {
    for (final view in [
      activeView(),
      const MemberPassView(status: PassStatus.loading),
      _noPass(NoPassState.notMember),
    ]) {
      await expectBuildsCleanly(
        tester,
        () => const MemberPassScreen(),
        overrides: overrides(view),
      );
    }
  });

  testWidgets('active shows the card and holds the codes', (tester) async {
    await pumpBisoScreen(
      tester,
      const MemberPassScreen(),
      overrides: overrides(activeView()),
    );
    expect(find.byType(PassCard), findsOneWidget);
    expect(pass.holds, 1);
  });

  testWidgets('tapping the card opens presentation mode', (tester) async {
    await pumpRouted(tester, activeView());
    await tester.tap(find.byType(PassCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MemberPassPresentation), findsOneWidget);
  });

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpBisoScreen(
      tester,
      const MemberPassScreen(),
      overrides: overrides(const MemberPassView(status: PassStatus.loading)),
    );
    expect(find.byType(BisoSkeleton), findsOneWidget);
  });

  final messages = <String, (MemberPassView, String, String)>{
    'no BI identity': (
      _noPass(NoPassState.noBiIdentity),
      'Link your BI student account',
      'Link on biso.no',
    ),
    'not a member': (
      _noPass(NoPassState.notMember),
      "You're not a member",
      'Become a member',
    ),
    'expired': (
      _noPass(NoPassState.expired),
      'Your membership has ended',
      'Become a member',
    ),
    'unavailable': (
      _noPass(NoPassState.unavailable),
      "Couldn't load your pass",
      'Try again',
    ),
    'reconnect': (
      const MemberPassView(status: PassStatus.reconnect, offline: true),
      'Reconnect to show your pass',
      'Try again',
    ),
    'signed out': (
      const MemberPassView(status: PassStatus.signedOut),
      'Sign in to see your pass',
      'Sign in',
    ),
  };
  messages.forEach((name, entry) {
    final (view, title, action) = entry;
    testWidgets('$name shows its message', (tester) async {
      await pumpBisoScreen(
        tester,
        const MemberPassScreen(),
        overrides: overrides(view),
      );
      expect(find.text(title), findsOneWidget);
      expect(find.widgetWithText(FilledButton, action), findsOneWidget);
      expect(find.byType(PassCard), findsNothing);
    });
  });

  testWidgets('Try again retries', (tester) async {
    await pumpBisoScreen(
      tester,
      const MemberPassScreen(),
      overrides: overrides(
        const MemberPassView(status: PassStatus.reconnect, offline: true),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    expect(pass.retries, 1);
  });

  testWidgets('Try again is disabled while a fetch runs', (tester) async {
    await pumpBisoScreen(
      tester,
      const MemberPassScreen(),
      overrides: overrides(
        const MemberPassView(status: PassStatus.reconnect, fetching: true),
      ),
    );
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Try again'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('linking opens biso.no and notes it for the re-check', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const MemberPassScreen(),
      overrides: overrides(_noPass(NoPassState.noBiIdentity)),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Link on biso.no'));
    await tester.pump();
    expect(launched, [membershipLinkUrl]);
    expect(overview.linkNoted, isTrue);
  });

  testWidgets('Become a member opens the membership screen', (tester) async {
    await pumpRouted(tester, _noPass(NoPassState.expired));
    await tester.tap(find.widgetWithText(FilledButton, 'Become a member'));
    await tester.pumpAndSettle();
    expect(find.text('Membership screen'), findsOneWidget);
  });

  testWidgets('Sign in opens the login screen', (tester) async {
    await pumpRouted(
      tester,
      const MemberPassView(status: PassStatus.signedOut),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Login screen'), findsOneWidget);
  });

  testWidgets('the Profile row opens the pass', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: MemberPassRow()),
        ),
        GoRoute(
          path: memberPassPath,
          builder: (_, _) => const Scaffold(body: Text('Pass screen')),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: PremiumTheme.build(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Member pass'), findsOneWidget);
    await tester.tap(find.byType(MemberPassRow));
    await tester.pumpAndSettle();
    expect(find.text('Pass screen'), findsOneWidget);
  });
}
