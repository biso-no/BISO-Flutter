import 'package:biso/data/models/member_pass.dart';
import 'package:biso/data/services/member_pass_api_client.dart';
import 'package:biso/providers/member_pass/scan_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('valid is green with the holder details', () {
    final expiry = DateTime(2026, 12, 31);
    expect(
      mapScanOutcome(
        ScanOutcome(
          result: ScanResult.valid,
          name: 'Kari',
          membershipName: 'Semester',
          expiryDate: expiry,
        ),
      ),
      ScannerResult(
        tone: ScanTone.green,
        message: ScanMessage.valid,
        name: 'Kari',
        membershipName: 'Semester',
        expiryDate: expiry,
      ),
    );
  });

  test('duplicate is orange with the seconds since', () {
    final result = mapScanOutcome(
      const ScanOutcome(
        result: ScanResult.duplicate,
        name: 'Kari',
        secondsSincePrevious: 42,
      ),
    );
    expect(result.tone, ScanTone.orange);
    expect(result.message, ScanMessage.duplicate);
    expect(result.secondsSincePrevious, 42);
    expect(result.name, 'Kari');
  });

  test('check_id is amber', () {
    final result = mapScanOutcome(
      const ScanOutcome(result: ScanResult.checkId, name: 'Kari'),
    );
    expect(result.tone, ScanTone.amber);
    expect(result.message, ScanMessage.checkId);
  });

  test('each denied reason is red with its own message', () {
    for (final (reason, message) in [
      (DenyReason.badCode, ScanMessage.badCode),
      (DenyReason.stale, ScanMessage.stale),
      (DenyReason.expired, ScanMessage.expired),
      (DenyReason.notMember, ScanMessage.notMember),
      (DenyReason.notLinked, ScanMessage.notLinked),
      (DenyReason.other, ScanMessage.notValid),
      (null, ScanMessage.notValid),
    ]) {
      final result = mapScanOutcome(
        ScanOutcome(result: ScanResult.denied, reason: reason),
      );
      expect(result.tone, ScanTone.red, reason: '$reason');
      expect(result.message, message, reason: '$reason');
    }
  });

  test('a denied result carries the server-supplied name through', () {
    final result = mapScanOutcome(
      const ScanOutcome(
        result: ScanResult.denied,
        reason: DenyReason.notMember,
        name: 'Kari',
      ),
    );
    expect(result.name, 'Kari');
  });

  test('unavailable is grey', () {
    expect(
      mapScanOutcome(const ScanOutcome(result: ScanResult.unavailable)),
      const ScannerResult(
        tone: ScanTone.grey,
        message: ScanMessage.unavailable,
      ),
    );
  });

  test('errors', () {
    MemberPassApiException status(int code) =>
        MemberPassApiException('x', statusCode: code);
    expect(
      mapScanError(status(401)),
      const ScannerClosed(ScannerCloseReason.signedOut),
    );
    expect(
      mapScanError(status(403)),
      const ScannerClosed(ScannerCloseReason.noAccess),
    );
    expect(
      mapScanError(status(429)),
      const ScannerResult(
        tone: ScanTone.grey,
        message: ScanMessage.rateLimited,
      ),
    );
    expect(mapScanError(status(400)), overlongCodeResult);
    for (final error in [
      status(500),
      status(503),
      const MemberPassApiException(MemberPassApiException.network),
      StateError('boom'),
    ]) {
      expect(
        mapScanError(error),
        const ScannerResult(
          tone: ScanTone.grey,
          message: ScanMessage.unavailable,
        ),
        reason: '$error',
      );
    }
  });

  test('an overlong code reads as not a BISO pass', () {
    expect(
      overlongCodeResult,
      const ScannerResult(tone: ScanTone.red, message: ScanMessage.badCode),
    );
    expect(maxScanCodeLength, 256);
  });
}
