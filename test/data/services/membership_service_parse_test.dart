import 'dart:convert';

import 'package:biso/data/services/membership_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 18);

  String body({String? expiryDate, bool status = true}) => jsonEncode({
    'membership': {
      r'$id': 'm1',
      'name': 'BISO Semester',
      'price': 350,
      'category': '12',
      'status': status,
      'expiryDate': ?expiryDate,
    },
  });

  group('MembershipService.parseVerification', () {
    test('a membership that has not expired is a member', () {
      final result = MembershipService.parseVerification(
        body(expiryDate: '2026-12-31T00:00:00.000Z'),
        now: now,
      );
      expect(result.isMember, isTrue);
      expect(result.membership?.name, 'BISO Semester');
    });

    test('a membership past its expiry date is not a member', () {
      final result = MembershipService.parseVerification(
        body(expiryDate: '2026-06-30T00:00:00.000Z'),
        now: now,
      );
      expect(result.isMember, isFalse);
      // Kept, so the profile can still say which membership lapsed.
      expect(result.membership, isNotNull);
    });

    test('a membership with no expiry date is a member', () {
      expect(
        MembershipService.parseVerification(body(), now: now).isMember,
        isTrue,
      );
    });

    test('status is the catalog option being on sale, not membership', () {
      // `memberships.status` marks an option as still offered. A member
      // whose option is no longer sold is still a member until it expires.
      final result = MembershipService.parseVerification(
        body(expiryDate: '2026-12-31T00:00:00.000Z', status: false),
        now: now,
      );
      expect(result.isMember, isTrue);
    });

    test('an error response is not a member', () {
      final result = MembershipService.parseVerification(
        jsonEncode({'error': 'No active membership found for this user'}),
        now: now,
      );
      expect(result.isMember, isFalse);
      expect(result.error, 'No active membership found for this user');
    });

    test('an unparseable body is not a member', () {
      expect(
        MembershipService.parseVerification('not json', now: now).isMember,
        isFalse,
      );
    });
  });
}
