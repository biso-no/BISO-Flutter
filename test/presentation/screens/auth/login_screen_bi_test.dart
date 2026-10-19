import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/services/bi_sign_in_service.dart';
import 'package:biso/data/services/bi_sync_api_client.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/screens/auth/login_screen.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/biso_screen_harness.dart';

const _biButton = 'Sign in with BI student account';
const _existingAccount =
    'BI could not sign you into your existing BISO account. Use a login link '
    'to your student email below, and let us know at biso.no/contact so we '
    'can fix the sign-in.';
const _failed =
    'We could not sign you in with BI. Please try again, or use a login link.';

/// Signed out until [signInWithBi] answers [outcome], after which it is in
/// [after].
class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth(this.outcome, {this.after = const AuthState()})
    : super(const AuthState());

  final BiSignInOutcome outcome;
  final AuthState after;
  int biSignIns = 0;

  @override
  Future<BiSignInOutcome> signInWithBi() async {
    biSignIns++;
    state = after;
    return outcome;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Auth auth;

  List<Override> overrides(
    BiSignInOutcome outcome, {
    AuthState after = const AuthState(),
  }) => [
    authStateProvider.overrideWith((_) => auth = _Auth(outcome, after: after)),
  ];

  Future<void> pumpRouted(
    WidgetTester tester,
    BiSignInOutcome outcome,
    AuthState after,
  ) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/auth/login',
      routes: [
        GoRoute(path: '/auth/login', builder: (_, _) => const LoginScreen()),
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('Home screen')),
        ),
        GoRoute(
          path: '/onboarding',
          builder: (_, _) => const Scaffold(body: Text('Onboarding screen')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(outcome, after: after),
        child: MaterialApp.router(
          theme: PremiumTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the BI button above the login-link form', (tester) async {
    await pumpBisoScreen(
      tester,
      const LoginScreen(),
      overrides: overrides(const BiSignInCancelled()),
      inShell: false,
    );

    expect(find.text(_biButton), findsOneWidget);
    expect(
      find.text(
        'BI students: your student membership and member prices follow your '
        'BI account.',
      ),
      findsOneWidget,
    );
    expect(find.text('Not a BI student? Use a login link'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(_biButton)).dy,
      lessThan(tester.getTopLeft(find.byType(TextFormField)).dy),
    );
  });

  testWidgets('shows no Google or Apple button', (tester) async {
    await pumpBisoScreen(
      tester,
      const LoginScreen(),
      overrides: overrides(const BiSignInCancelled()),
      inShell: false,
    );

    expect(find.textContaining('Google'), findsNothing);
    expect(find.textContaining('Apple'), findsNothing);
  });

  testWidgets('a cancelled sign-in shows nothing', (tester) async {
    await pumpBisoScreen(
      tester,
      const LoginScreen(),
      overrides: overrides(const BiSignInCancelled()),
      inShell: false,
    );

    await tester.tap(find.text(_biButton));
    await tester.pumpAndSettle();

    expect(auth.biSignIns, 1);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text(_failed), findsNothing);
    expect(find.text(_existingAccount), findsNothing);
    // The screen is usable again.
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(_biButton),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('existing-account failure shows the web copy', (tester) async {
    await pumpBisoScreen(
      tester,
      const LoginScreen(),
      overrides: overrides(
        const BiSignInFailed(BiSignInFailure.existingAccount),
      ),
      inShell: false,
    );

    await tester.tap(find.text(_biButton));
    await tester.pumpAndSettle();

    expect(find.text(_existingAccount), findsOneWidget);
    expect(find.text(_failed), findsNothing);
  });

  testWidgets('any other failure shows the web copy', (tester) async {
    await pumpBisoScreen(
      tester,
      const LoginScreen(),
      overrides: overrides(const BiSignInFailed(BiSignInFailure.failed)),
      inShell: false,
    );

    await tester.tap(find.text(_biButton));
    await tester.pumpAndSettle();

    expect(find.text(_failed), findsOneWidget);
  });

  testWidgets('a BI sign-in goes home', (tester) async {
    await pumpRouted(
      tester,
      const BiSignedIn(BiSyncResult(success: true, studentId: 's1234567')),
      const AuthState(isAuthenticated: true, isProfileComplete: true),
    );

    await tester.tap(find.text(_biButton));
    await tester.pumpAndSettle();

    expect(find.text('Home screen'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a new student goes to onboarding', (tester) async {
    await pumpRouted(
      tester,
      const BiSignedIn(BiSyncResult(success: true, studentId: 's1234567')),
      const AuthState(isAuthenticated: true),
    );

    await tester.tap(find.text(_biButton));
    await tester.pumpAndSettle();

    expect(find.text('Onboarding screen'), findsOneWidget);
  });

  testWidgets('a sync error is shown and the student stays signed in', (
    tester,
  ) async {
    await pumpRouted(
      tester,
      const BiSignedIn(
        BiSyncResult(success: false, error: BiSyncError.invalidBiEmail),
      ),
      const AuthState(isAuthenticated: true, isProfileComplete: true),
    );

    await tester.tap(find.text(_biButton));
    await tester.pumpAndSettle();

    expect(find.text('Home screen'), findsOneWidget);
    expect(
      find.text(
        'The BI account you signed in with is not a student account. Sign in '
        'with the student account for your s-number (s1234567@bi.no).',
      ),
      findsOneWidget,
    );
  });

  testWidgets('directory_unavailable signs in without an error', (
    tester,
  ) async {
    await pumpRouted(
      tester,
      const BiSignedIn(
        BiSyncResult(success: false, error: BiSyncError.directoryUnavailable),
      ),
      const AuthState(isAuthenticated: true, isProfileComplete: true),
    );

    await tester.tap(find.text(_biButton));
    await tester.pumpAndSettle();

    expect(find.text('Home screen'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });
}
