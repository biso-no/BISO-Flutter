import 'package:biso/presentation/screens/auth/login_screen.dart';
import 'package:biso/presentation/screens/auth/magic_link_verify_screen.dart';
import 'package:biso/presentation/screens/auth/otp_verification_screen.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

/// A signed-out auth state, mirroring the `_Auth` pattern used across the
/// other screen design tests (`profile_design_test.dart`,
/// `profile_forms_design_test.dart`): a `StateNotifier` faked via
/// `noSuchMethod` so no method call reaches a real `AuthService` or network.
class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth() : super(const AuthState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> _overrides() => [authStateProvider.overrideWith((_) => _Auth())];

void main() {
  testWidgets(
    'Login builds on BisoPage in every appearance, as a top-level route',
    (tester) async {
      await expectBuildsCleanly(
        tester,
        () => const LoginScreen(),
        overrides: _overrides(),
        inShell: false,
      );
    },
  );

  testWidgets(
    'Login builds on BisoPage in every appearance, pushed from Home',
    (tester) async {
      await expectBuildsCleanly(
        tester,
        () => const LoginScreen(),
        overrides: _overrides(),
        inShell: true,
      );
    },
  );

  testWidgets('OTP verification builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const OtpVerificationScreen(email: 'student@bi.no'),
      overrides: _overrides(),
      inShell: false,
    );
  });

  testWidgets('Magic link verify builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const MagicLinkVerifyScreen(userId: 'u1', secret: 'a-secret'),
      overrides: _overrides(),
      inShell: false,
    );
  });

  for (final inShell in [false, true]) {
    testWidgets(
      'Login builds without overflow at text scale 2 on a 320x640 screen '
      'with a 300pt keyboard, and the send button can be scrolled into view '
      '(inShell: $inShell)',
      (tester) async {
        // Matches the device pixel ratio pumpBisoScreen fixes internally, so
        // the keyboard inset below lands at the intended 300 logical points.
        const dpr = 3.0;
        tester.view.viewInsets = const FakeViewPadding(bottom: 300 * dpr);
        addTearDown(tester.view.resetViewInsets);

        await pumpBisoScreen(
          tester,
          const LoginScreen(),
          overrides: _overrides(),
          textScale: 2,
          size: const Size(320, 640),
          inShell: inShell,
        );
        expect(tester.takeException(), isNull);

        // The email field's own EditableText owns a second (horizontal)
        // Scrollable, so the page's CustomScrollView — first in tree order,
        // as its ancestor — must be named explicitly.
        await tester.scrollUntilVisible(
          find.text('Send me a sign-in link'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();

        expect(find.text('Send me a sign-in link'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
