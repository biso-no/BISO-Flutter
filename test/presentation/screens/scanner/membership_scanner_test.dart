import 'dart:async';

import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/models/member_pass.dart';
import 'package:biso/data/services/member_pass_api_client.dart';
import 'package:biso/data/services/scanner_camera.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/screens/scanner/membership_scanner_screen.dart';
import 'package:biso/presentation/screens/scanner/scanner_gate.dart';
import 'package:biso/presentation/screens/scanner/scanner_route.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/member_pass/member_pass_provider.dart';
import 'package:biso/providers/member_pass/scan_display.dart';
import 'package:biso/providers/member_pass/scanner_access_provider.dart';
import 'package:biso/providers/member_pass/scanner_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/biso_screen_harness.dart';
import '../../../helpers/fake_member_pass_api.dart';

void main() {
  late FakeMemberPassApi api;
  late FakeScannerCamera camera;
  late int camerasMade;
  late FixedScannerAccess access;
  late List<ScanTone> haptics;

  final expiring = ScannerGranted(
    ScannerAccess(
      dayColor: testDayColor,
      expiresAt: DateTime.utc(2026, 9, 20, 22),
    ),
  );

  List<Override> overrides(ScannerAccessState? state) {
    api = FakeMemberPassApi()
      ..onScan = (_) => ScanOutcome(
        result: ScanResult.valid,
        name: 'Kari Nordmann',
        membershipName: 'Semester',
        expiryDate: DateTime(2026, 12, 31),
      );
    camera = FakeScannerCamera();
    camerasMade = 0;
    access = FixedScannerAccess(state);
    haptics = [];
    return [
      memberPassApiProvider.overrideWithValue(api),
      scannerAccessProvider.overrideWith(() => access),
      scanHapticsProvider.overrideWithValue(haptics.add),
      scannerCameraFactoryProvider.overrideWithValue(() {
        camerasMade++;
        return camera;
      }),
    ];
  }

  Future<void> pumpGate(WidgetTester tester, ScannerAccessState? state) =>
      pumpBisoScreen(
        tester,
        const ScannerGate(),
        overrides: overrides(state),
        inShell: false,
        routed: true,
      );

  group('gate', () {
    testWidgets('shows a spinner and no camera while checking', (tester) async {
      await pumpGate(tester, null);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(camerasMade, 0);
    });

    final messages = {
      'denied': (
        const ScannerDenied(),
        "You don't have scanning access. Ask BISO staff for an invitation.",
      ),
      'signed out': (
        const ScannerSignedOut(),
        "You've been signed out — sign in again",
      ),
      'not configured': (
        const ScannerNotConfigured(),
        "Scanning isn't available right now.",
      ),
      'failed': (const ScannerCheckFailed(), "Couldn't check your access"),
    };
    messages.forEach((name, entry) {
      final (state, text) = entry;
      testWidgets('$name shows its message and no camera', (tester) async {
        await pumpGate(tester, state);
        expect(find.text(text), findsOneWidget);
        expect(camerasMade, 0);
        expect(find.byType(BisoPage), findsOneWidget);
      });
    });

    testWidgets('a failed check can be retried', (tester) async {
      await pumpGate(tester, const ScannerCheckFailed());
      final before = access.freshCalls;
      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      expect(access.freshCalls, before + 1);
    });

    testWidgets('granted opens the camera and refreshes access', (
      tester,
    ) async {
      await pumpGate(tester, expiring);
      expect(find.byType(MembershipScannerScreen), findsOneWidget);
      expect(find.byKey(const Key('fake-camera')), findsOneWidget);
      expect(camerasMade, 1);
      expect(access.freshCalls, 1);
    });
  });

  group('scanner', () {
    testWidgets('the top bar shows the day color and the access end', (
      tester,
    ) async {
      await pumpGate(tester, expiring);
      expect(find.text('Teal'), findsOneWidget);
      expect(find.textContaining('Access until'), findsOneWidget);
      expect(find.text('Point the camera at a member pass'), findsOneWidget);
    });

    testWidgets('a valid read fills the screen, stops, then resumes', (
      tester,
    ) async {
      await pumpGate(tester, expiring);
      camera.read('v1.kari.1.sig');
      await tester.pump();
      await tester.pump();

      expect(find.text('Valid member'), findsOneWidget);
      expect(find.text('Kari Nordmann'), findsOneWidget);
      expect(find.textContaining('Valid until'), findsOneWidget);
      // Stopped, not paused: a paused session would survive backgrounding.
      expect(camera.stops, 1);
      expect(haptics, [ScanTone.green]);

      await tester.pump(ScannerController.resultDuration);
      await tester.pump();
      expect(find.text('Valid member'), findsNothing);
      expect(camera.resumes, 1);
    });

    testWidgets('a tap dismisses the result', (tester) async {
      await pumpGate(tester, expiring);
      camera.read('v1.kari.1.sig');
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Tap to continue'));
      await tester.pump();
      expect(find.text('Valid member'), findsNothing);
      expect(camera.resumes, 1);
    });

    testWidgets('the camera stops while backgrounded and resumes on return', (
      tester,
    ) async {
      await pumpGate(tester, expiring);

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      expect(camera.stops, 1);

      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      expect(camera.resumes, 1);
    });

    testWidgets(
      'a result showing keeps the camera off until it is dismissed, even '
      'after a background and return',
      (tester) async {
        await pumpGate(tester, expiring);
        camera.read('v1.kari.1.sig');
        await tester.pump();
        await tester.pump();
        expect(find.text('Valid member'), findsOneWidget);
        expect(camera.stops, 1);

        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        // Stopping again is harmless and covers a start that raced it.
        expect(camera.stops, 2);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        expect(camera.resumes, 0);

        await tester.pump(ScannerController.resultDuration);
        await tester.pump();
        expect(find.text('Valid member'), findsNothing);
        expect(camera.resumes, 1);
      },
    );

    testWidgets(
      "a result's own timer dismissing it while still backgrounded does not "
      'resume the camera; only the later return to the foreground does',
      (tester) async {
        await pumpGate(tester, expiring);
        camera.read('v1.kari.1.sig');
        await tester.pump();
        await tester.pump();
        expect(find.text('Valid member'), findsOneWidget);

        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }

        // Advances the auto-dismiss timer while still backgrounded. Frames
        // are disabled in this lifecycle state, so the screen itself is not
        // rebuilt yet (asserting on it would test the harness, not this
        // fix) — but the provider's own timer still fires and notifies
        // listeners, which is exactly the path this fix must guard.
        await tester.pump(ScannerController.resultDuration);
        expect(camera.resumes, 0);

        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        expect(camera.resumes, 1);
      },
    );

    final outcomes = <String, (ScanOutcome, String)>{
      'duplicate': (
        const ScanOutcome(
          result: ScanResult.duplicate,
          name: 'Kari',
          secondsSincePrevious: 42,
        ),
        'Already scanned 42s ago',
      ),
      'check id': (
        const ScanOutcome(result: ScanResult.checkId, name: 'Kari'),
        'Wallet pass — check ID',
      ),
      'stale': (
        const ScanOutcome(result: ScanResult.denied, reason: DenyReason.stale),
        'Old code — ask them to reopen the pass',
      ),
      'not linked': (
        const ScanOutcome(
          result: ScanResult.denied,
          reason: DenyReason.notLinked,
        ),
        'No linked student account',
      ),
      'unavailable': (
        const ScanOutcome(result: ScanResult.unavailable),
        "Couldn't check — try again",
      ),
    };
    outcomes.forEach((name, entry) {
      final (outcome, text) = entry;
      testWidgets('$name shows "$text"', (tester) async {
        await pumpGate(tester, expiring);
        api.onScan = (_) => outcome;
        camera.read('v1.kari.1.sig');
        await tester.pump();
        await tester.pump();
        expect(find.text(text), findsOneWidget);
        await tester.pump(ScannerController.resultDuration);
      });
    });

    testWidgets('a rate limit says to wait', (tester) async {
      await pumpGate(tester, expiring);
      api.onScan = (_) =>
          throw const MemberPassApiException('rate_limited', statusCode: 429);
      camera.read('v1.kari.1.sig');
      await tester.pump();
      await tester.pump();
      expect(find.text('Too many scans — wait a moment'), findsOneWidget);
      await tester.pump(ScannerController.resultDuration);
    });

    testWidgets('an overlong read is denied without a request', (tester) async {
      await pumpGate(tester, expiring);
      camera.read('x' * 300);
      await tester.pump();
      expect(find.text('Not a BISO pass'), findsOneWidget);
      expect(api.scanned, isEmpty);
      await tester.pump(ScannerController.resultDuration);
    });

    testWidgets('a 403 mid-shift closes the scanner with a message', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/explore',
        routes: [
          membershipScannerRoute(),
          GoRoute(
            path: '/explore',
            builder: (_, _) => const Scaffold(body: Text('Explore')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(expiring),
          child: MaterialApp.router(
            theme: PremiumTheme.build(Brightness.light),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      unawaited(router.push(membershipScannerPath));
      await tester.pumpAndSettle();
      expect(find.byType(MembershipScannerScreen), findsOneWidget);

      api.onScan = (_) =>
          throw const MemberPassApiException('not_scanner', statusCode: 403);
      camera.read('v1.kari.1.sig');
      await tester.pumpAndSettle();

      expect(find.byType(MembershipScannerScreen), findsNothing);
      expect(find.text('Explore'), findsOneWidget);
      expect(
        find.text(
          "You don't have scanning access. Ask BISO staff for an invitation.",
        ),
        findsOneWidget,
      );
      expect(camera.disposed, isTrue);
    });
  });

  testWidgets('the route is matched ahead of the tab shell', (tester) async {
    final router = GoRouter(
      initialLocation: membershipScannerPath,
      routes: [
        membershipScannerRoute(),
        ShellRoute(
          builder: (_, _, child) => child,
          routes: [
            GoRoute(
              path: '/explore',
              builder: (_, _) => const Text('Explore'),
              routes: [
                GoRoute(
                  path: '/events',
                  builder: (_, _) => const Text('Events'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(const ScannerDenied()),
        child: MaterialApp.router(
          theme: PremiumTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ScannerGate), findsOneWidget);
  });
}
