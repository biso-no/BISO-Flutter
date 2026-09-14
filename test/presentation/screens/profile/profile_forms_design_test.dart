import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/screens/profile/edit_profile_screen.dart';
import 'package:biso/presentation/screens/profile/payment_information_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

const _user = UserModel(
  id: 'u1',
  name: 'Test Student',
  email: 'student@bi.no',
  phone: '12345678',
  address: 'Testveien 1',
  city: 'Oslo',
  zipCode: '0170',
  bankAccount: '12345678901',
  departments: ['BISO Oslo'],
);

/// A signed-in user with no payment info yet, mirroring `profile_design_test`'s
/// `_Auth` pattern (a `StateNotifier` faked via `noSuchMethod`).
class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth()
    : super(
        const AuthState(
          isAuthenticated: true,
          user: _user,
          isProfileComplete: true,
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records `updateProfile` calls instead of hitting a real `AuthService`, so
/// the save action can be asserted without network access.
class _RecordingAuth extends StateNotifier<AuthState> implements AuthNotifier {
  _RecordingAuth()
    : super(
        const AuthState(
          isAuthenticated: true,
          user: _user,
          isProfileComplete: true,
        ),
      );

  int updateProfileCalls = 0;

  @override
  Future<void> updateProfile({
    String? name,
    String? phone,
    String? address,
    String? city,
    String? zipCode,
    String? campusId,
    List<String>? departments,
    dynamic avatarFile,
  }) async {
    updateProfileCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Payment information builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const PaymentInformationScreen(),
      overrides: [authStateProvider.overrideWith((_) => _Auth())],
    );
  });

  testWidgets('Edit profile builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const EditProfileScreen(),
      overrides: [authStateProvider.overrideWith((_) => _Auth())],
    );
  });

  testWidgets(
    'Payment information toggling account type reveals the SWIFT group',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const PaymentInformationScreen(),
        overrides: [authStateProvider.overrideWith((_) => _Auth())],
      );
      await tester.pumpAndSettle();

      expect(find.text('SWIFT/BIC Code'), findsNothing);

      await tester.tap(find.text('Norwegian Bank Account'));
      await tester.pumpAndSettle();

      expect(find.text('International Bank Account'), findsOneWidget);
      expect(find.text('SWIFT/BIC Code'), findsOneWidget);
    },
  );

  testWidgets(
    'Payment information bank account number never truncates at 390pt, 1.6x '
    '(R11)',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const PaymentInformationScreen(),
        overrides: [authStateProvider.overrideWith((_) => _Auth())],
        textScale: 1.6,
        size: const Size(390, 844),
      );
      await tester.pumpAndSettle();

      // Type a full 11-digit number; the field's own formatter inserts the
      // spaces, mirroring what a real long account number looks like. Only
      // the Norwegian account field is present at this point (International
      // is off by default), so the first TextFormField is unambiguous.
      await tester.enterText(find.byType(TextFormField).first, '86011117947');
      await tester.pumpAndSettle();

      expect(find.text('8601 11 17947'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets("Edit profile's save action calls updateProfile once", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final auth = _RecordingAuth();

    // Pushed with MaterialPageRoute, as it is from ProfileScreen, so there is
    // a route beneath it for the screen's own `Navigator.pop(context)` (kept
    // unchanged from before the migration) to return to.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authStateProvider.overrideWith((_) => auth)],
        child: MaterialApp(
          theme: PremiumTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const EditProfileScreen(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(auth.updateProfileCalls, 1);
  });

  testWidgets(
    'the avatar photo button is a plain raised circle, not glass, with a '
    '44pt tap target',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const EditProfileScreen(),
        overrides: [authStateProvider.overrideWith((_) => _Auth())],
      );
      await tester.pumpAndSettle();

      final button = find.byTooltip('Change photo');
      expect(button, findsOneWidget);
      expect(
        // Header actions keep their glass; only the avatar button loses it.
        find.ancestor(of: button, matching: find.byType(BisoGlassCapsule)),
        findsNothing,
      );
      expect(
        find.ancestor(of: button, matching: find.byType(BackdropFilter)),
        findsNothing,
      );
      final size = tester.getSize(button);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    },
  );
}
