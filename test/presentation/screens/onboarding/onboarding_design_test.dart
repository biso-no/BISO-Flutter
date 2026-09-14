import 'package:biso/presentation/screens/onboarding/onboarding_screen.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

/// A signed-out, not-loading auth state, mirroring the `_Auth` pattern used
/// across the other screen design tests (`auth_design_test.dart`,
/// `profile_design_test.dart`): a `StateNotifier` faked via `noSuchMethod` so
/// no method call reaches a real `AuthService` or network.
class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth() : super(const AuthState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> _overrides() => [authStateProvider.overrideWith((_) => _Auth())];

void main() {
  testWidgets('Onboarding builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const OnboardingScreen(),
      overrides: _overrides(),
      inShell: false,
    );
  });

  testWidgets(
    'Onboarding step 1 has no back button, and the top spacer equals the '
    'header inset',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const OnboardingScreen(),
        overrides: _overrides(),
        inShell: false,
      );
      expect(tester.takeException(), isNull);

      // notch padding (47) + header height (52), per BisoPageInsets.
      final spacer = tester.widget<SizedBox>(
        find.byKey(const ValueKey('step-top-inset')).first,
      );
      expect(spacer.height, 99);
      expect(spacer.height, greaterThan(0));

      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing);
    },
  );

  testWidgets(
    'Filling the required field and tapping Continue advances to step 2, '
    'showing "2 / 2" and a back button, at text scale 1.6 on a 320x640 '
    'screen',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const OnboardingScreen(),
        overrides: _overrides(),
        inShell: false,
        textScale: 1.6,
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);

      // The name field is the only required one on step 1.
      await tester.enterText(find.byType(TextFormField).first, 'Ola Nordmann');
      await tester.pump();

      // Step 1's own CustomScrollView is the first one built (step 2's is a
      // sibling further along the PageView's child list); scroll its actual
      // Scrollable descendant, not the outer never-scrollable PageView.
      await tester.scrollUntilVisible(
        find.text('Continue'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Continue'));
      // The step transition animates over 300ms.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);

      // The campus list survived the migration: all four campuses render
      // (scrolling step 2's own Scrollable, since only the first two fit the
      // 320x640 viewport at this text scale), and selecting one shows the
      // checkmark and enables Complete Setup without submitting anything
      // (createProfile is never called here). Step 1's CustomScrollView is
      // no longer built once scrolled off the PageView's cache extent, so
      // step 2's is `.first` here, unlike before the transition above.
      final step2Scrollable = find
          .descendant(
            of: find.byType(CustomScrollView).first,
            matching: find.byType(Scrollable),
          )
          .first;
      expect(find.text('Oslo'), findsOneWidget);
      expect(find.text('Bergen'), findsOneWidget);

      // Select Oslo before scrolling: once scrolled, the first row would sit
      // under the translucent header, which (correctly) does not forward
      // taps to content beneath it.
      await tester.tap(find.text('Oslo'));
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.text('Stavanger'),
        200,
        scrollable: step2Scrollable,
      );
      expect(find.text('Trondheim'), findsOneWidget);
      expect(find.text('Stavanger'), findsOneWidget);

      final completeSetup = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Complete Setup'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(completeSetup.onPressed, isNotNull);
    },
  );

  testWidgets(
    'Continue stays reachable at text scale 1.6 on 320x640 with a 300pt '
    'keyboard',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const OnboardingScreen(),
        overrides: _overrides(),
        inShell: false,
        textScale: 1.6,
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);

      const dpr = 3.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * dpr);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Step 1's own CustomScrollView is the first one built (step 2's is a
      // sibling further along the PageView's child list); scroll its actual
      // Scrollable descendant, not the outer never-scrollable PageView.
      await tester.scrollUntilVisible(
        find.text('Continue'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump();

      expect(find.text('Continue'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
