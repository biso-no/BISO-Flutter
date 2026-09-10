import 'package:biso/data/services/notification_service.dart';
import 'package:biso/presentation/widgets/notification_permission_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      'each outcome maps to exactly one message, and unavailable/'
      'partiallyFailed intentionally share the same one, so the app never '
      'describes either state two different ways',
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

        expect(unavailable, partiallyFailed);
        expect(applied, isNot(unavailable));
      },
    );

    test(
      'permissionDenied is asserted rather than silently handled, since it '
      'cannot occur on the granted-permission path this is only ever called '
      'from',
      () {
        expect(
          () => snackBarForGrantedOutcome(ReconcileOutcome.permissionDenied),
          throwsA(isA<AssertionError>()),
        );
      },
    );
  });
}
