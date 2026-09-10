import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:biso/core/constants/notification_topics.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/auth_service.dart';
import 'package:biso/data/services/notification_service.dart';
import 'package:biso/presentation/widgets/notification_permission_dialog.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/notification/notification_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [NotificationService] for which permission is always granted, and whose
/// reconcile reports [outcome]. Every method the dialog reaches is overridden,
/// so its [Account] is never touched.
class _GrantingNotificationService extends NotificationService {
  _GrantingNotificationService(this.outcome)
    : super.withAccount(Account(Client()));

  final ReconcileOutcome outcome;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<ReconcileOutcome> reconcile({required String? campusId}) async =>
      outcome;

  @override
  Future<bool> getChatNotificationPreference() async => true;

  @override
  Future<void> updateChatNotificationPreference(bool enabled) async {}

  @override
  Future<Map<String, bool>> loadTopicIntent() async =>
      Map<String, bool>.from(kDefaultTopicIntent);
}

/// Resolves the session to "nobody signed in" without a network call, so the
/// dialog's read of the student's campus has an [AuthNotifier] to read.
class _SignedOutAuthService extends AuthService {
  @override
  Future<UserModel?> getCurrentUser() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Constructing an Appwrite Client asks path_provider for a cookie
    // directory, which has no implementation under `flutter test`.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  group('snackBarForGrantedOutcome (finding 5)', () {
    String textOf(SnackBar snackBar) => (snackBar.content as Text).data!;

    test('applied keeps the celebratory message', () {
      final snackBar = snackBarForGrantedOutcome(ReconcileOutcome.applied);

      expect(textOf(snackBar), contains('🎉'));
      expect(textOf(snackBar), contains('Notifications enabled'));
    });

    test(
      'unavailable says notifications are on but this device could not be '
      'updated, instead of unconditionally celebrating a subscription that '
      'does not exist',
      () {
        final snackBar = snackBarForGrantedOutcome(
          ReconcileOutcome.unavailable,
        );

        expect(textOf(snackBar), isNot(contains('🎉')));
        expect(textOf(snackBar), contains('could not be updated'));
        expect(textOf(snackBar), contains('retry'));
      },
    );

    test(
      'partiallyFailed gets the same treatment as unavailable - both leave '
      'this device without a full subscription',
      () {
        final snackBar = snackBarForGrantedOutcome(
          ReconcileOutcome.partiallyFailed,
        );

        expect(textOf(snackBar), isNot(contains('🎉')));
        expect(textOf(snackBar), contains('could not be updated'));
        expect(textOf(snackBar), contains('retry'));
      },
    );

    test(
      'each outcome maps to exactly one message, and every outcome but '
      'applied intentionally shares the same one, so the app never describes '
      'one state two different ways',
      () {
        final applied = textOf(
          snackBarForGrantedOutcome(ReconcileOutcome.applied),
        );
        final unavailable = textOf(
          snackBarForGrantedOutcome(ReconcileOutcome.unavailable),
        );
        final partiallyFailed = textOf(
          snackBarForGrantedOutcome(ReconcileOutcome.partiallyFailed),
        );
        final permissionDenied = textOf(
          snackBarForGrantedOutcome(ReconcileOutcome.permissionDenied),
        );

        expect(unavailable, partiallyFailed);
        expect(permissionDenied, unavailable);
        expect(applied, isNot(unavailable));
      },
    );

    test(
      'permissionDenied also says this device could not be updated, rather '
      'than celebrating or asserting: reconcile() re-reads the permission '
      'itself, and nothing guarantees that read agrees with the grant a '
      'moment earlier. The assert it replaces threw in debug after the '
      'dialog had already popped, so the dialog popped a second time',
      () {
        final snackBar = snackBarForGrantedOutcome(
          ReconcileOutcome.permissionDenied,
        );

        expect(textOf(snackBar), isNot(contains('🎉')));
        expect(textOf(snackBar), contains('could not be updated'));
      },
    );
  });

  group('NotificationPermissionDialog, once permission is granted', () {
    /// Opens the dialog from a screen pushed over home, taps Enable, and lets
    /// everything settle. The pushed screen is what a second pop would close.
    Future<void> enableFromDialog(
      WidgetTester tester,
      ReconcileOutcome outcome,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationServiceProvider.overrideWithValue(
              _GrantingNotificationService(outcome),
            ),
            authStateProvider.overrideWith(
              (ref) => AuthNotifier(_SignedOutAuthService()),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => Scaffold(
                        body: ElevatedButton(
                          onPressed: () =>
                              NotificationPermissionDialog.show(context),
                          child: const Text('screen underneath'),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('home'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('screen underneath'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationPermissionDialog), findsOneWidget);

      await tester.tap(find.text('Enable'));
      await tester.pumpAndSettle();
    }

    testWidgets('applied: celebrates, and closes only the dialog', (
      tester,
    ) async {
      await enableFromDialog(tester, ReconcileOutcome.applied);

      expect(find.textContaining('Notifications enabled!'), findsOneWidget);
      expect(find.byType(NotificationPermissionDialog), findsNothing);
      expect(find.text('screen underneath'), findsOneWidget);
    });

    for (final outcome in [
      ReconcileOutcome.unavailable,
      ReconcileOutcome.partiallyFailed,
      ReconcileOutcome.permissionDenied,
    ]) {
      testWidgets(
        '${outcome.name}: says this device could not be updated, never '
        '"Notifications enabled!" - so putting back a fixed celebratory '
        'snackbar fails this - and closes only the dialog',
        (tester) async {
          await enableFromDialog(tester, outcome);

          expect(find.byType(NotificationPermissionDialog), findsNothing);
          expect(
            find.text('screen underneath'),
            findsOneWidget,
            reason: 'a throw after the dialog popped lands in its catch, '
                'which pops again and closes the screen underneath',
          );
          expect(find.textContaining('could not be updated'), findsOneWidget);
          expect(find.textContaining('Notifications enabled!'), findsNothing);
        },
      );
    }
  });
}
