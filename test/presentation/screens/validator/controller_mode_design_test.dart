import 'package:biso/data/models/validation_result_model.dart';
import 'package:biso/data/services/validator_service.dart';
import 'package:biso/presentation/screens/validator/controller_mode_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../helpers/biso_screen_harness.dart';

/// `verifyPassToken` is the only member the screen calls; everything else is
/// left to `noSuchMethod`.
class _FakeValidatorService implements ValidatorService {
  _FakeValidatorService(this.result);

  final ValidationResultModel result;

  @override
  Future<ValidationResultModel> verifyPassToken({
    required String token,
    Map<String, dynamic>? context,
  }) async => result;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The screen only ever shows an error reason for a token the verify call
/// rejected outright (`catch (e) { _lastError = e.toString(); }`); a
/// successful INVALID response without member info renders no detail text,
/// which is today's actual (unchanged) behavior.
class _ThrowingValidatorService implements ValidatorService {
  _ThrowingValidatorService(this.message);

  final String message;

  @override
  Future<ValidationResultModel> verifyPassToken({
    required String token,
    Map<String, dynamic>? context,
  }) async => throw Exception(message);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _validResult = ValidationResultModel(
  ok: true,
  result: 'VALID',
  member: MemberInfo(
    displayName: 'Jane Student',
    membershipName: 'BISO Membership',
    expiresAt: '2027-01-01',
  ),
);

void main() {
  testWidgets('Controller mode screen builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => ControllerModeScreen(
        scannerBuilder: (_) => const ColoredBox(color: Color(0xFF000000)),
      ),
    );
  });

  testWidgets(
    "the instruction card clears the header and shows the last scan's time "
    'after a scan',
    (tester) async {
      void Function(BarcodeCapture)? detect;

      await pumpBisoScreen(
        tester,
        ControllerModeScreen(
          scannerBuilder: (onDetect) {
            detect = onDetect;
            return const ColoredBox(color: Color(0xFF000000));
          },
          validatorService: _FakeValidatorService(_validResult),
        ),
      );

      final topLeft = tester.getTopLeft(
        find.byKey(const Key('controllerModeInstructionCard')),
      );
      // Harness sets a 47pt top padding; the card must clear the 52pt header
      // drawn below it, i.e. sit no higher than padding.top + header height.
      expect(topLeft.dy, greaterThanOrEqualTo(47 + kBisoHeaderHeight));

      expect(detect, isNotNull);
      detect!(
        const BarcodeCapture(barcodes: [Barcode(rawValue: 'valid-token')]),
      );
      await tester.pump();
      // Flush the second selectionClick delay in the VALID haptic sequence.
      await tester.pump(const Duration(milliseconds: 150));
      // Let the elastic result animation and pulse settle to a steady frame.
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.textContaining('Last scan:'), findsOneWidget);
    },
  );

  testWidgets('shows the valid result card after a successful scan', (
    tester,
  ) async {
    void Function(BarcodeCapture)? detect;

    await pumpBisoScreen(
      tester,
      ControllerModeScreen(
        scannerBuilder: (onDetect) {
          detect = onDetect;
          return const ColoredBox(color: Color(0xFF000000));
        },
        validatorService: _FakeValidatorService(_validResult),
      ),
    );

    detect!(const BarcodeCapture(barcodes: [Barcode(rawValue: 'valid-token')]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('VALID MEMBER'), findsOneWidget);
    expect(find.text('Jane Student'), findsOneWidget);
    expect(find.text('BISO Membership'), findsOneWidget);
    expect(find.textContaining('Expires:'), findsOneWidget);
    expect(find.text('Continue Scanning'), findsOneWidget);

    // Reset flow stays available and clears the result.
    await tester.tap(find.text('Continue Scanning'));
    await tester.pump();
    expect(find.text('VALID MEMBER'), findsNothing);
  });

  testWidgets('shows the invalid result card with the error reason', (
    tester,
  ) async {
    void Function(BarcodeCapture)? detect;

    await pumpBisoScreen(
      tester,
      ControllerModeScreen(
        scannerBuilder: (onDetect) {
          detect = onDetect;
          return const ColoredBox(color: Color(0xFF000000));
        },
        validatorService: _ThrowingValidatorService('Token has expired'),
      ),
    );

    detect!(
      const BarcodeCapture(barcodes: [Barcode(rawValue: 'invalid-token')]),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('INVALID'), findsOneWidget);
    expect(find.text('Exception: Token has expired'), findsOneWidget);
    expect(find.text('Continue Scanning'), findsOneWidget);
  });
}
