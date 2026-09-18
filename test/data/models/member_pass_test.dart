import 'dart:ui' show Color;

import 'package:biso/data/models/member_pass.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> activeJson() => {
  'state': 'active',
  'holder': {
    'name': 'Markus Heien',
    'membershipName': 'Semester',
    'startDate': '2026-07-01',
    'expiryDate': '2026-12-31',
    'term': {
      'duration': 'semester',
      'season': 'fall',
      'fromYear': 2026,
      'toYear': 2026,
    },
  },
  'codes': [
    {'slot': 59654565, 'code': 'v1.u.59654565.b'},
    {'slot': 59654564, 'code': 'v1.u.59654564.a'},
  ],
  'dayColor': {'name': 'teal', 'hex': '#12A594'},
  'serverNow': 1789636920000,
  'wallets': {'apple': true, 'google': false},
};

void main() {
  test('parses an active pass with codes in slot order', () {
    final pass = MemberPassResponse.fromJson(activeJson()) as ActivePass;
    expect(pass.holder.name, 'Markus Heien');
    expect(pass.holder.membershipName, 'Semester');
    expect(pass.holder.expiryDate, DateTime(2026, 12, 31));
    expect(pass.codes.map((c) => c.slot), [59654564, 59654565]);
    expect(pass.serverNow, 1789636920000);
    expect(pass.dayColor.color, const Color(0xFF12A594));
    expect(pass.wallets, const WalletAvailability(apple: true, google: false));
  });

  test('an active body with no usable codes is unavailable', () {
    final json = activeJson()
      ..['codes'] = [
        {'slot': 'x', 'code': ''},
      ];
    expect(
      MemberPassResponse.fromJson(json),
      const NoPass(NoPassState.unavailable),
    );
  });

  test('parses each no-pass state and treats unknown ones as unavailable', () {
    for (final (value, state) in [
      ('no_bi_identity', NoPassState.noBiIdentity),
      ('not_member', NoPassState.notMember),
      ('expired', NoPassState.expired),
      ('unavailable', NoPassState.unavailable),
      ('something_new', NoPassState.unavailable),
    ]) {
      expect(MemberPassResponse.fromJson({'state': value}), NoPass(state));
    }
  });

  test('term labels', () {
    const fall = PassTerm(
      duration: TermDuration.semester,
      season: TermSeason.fall,
      fromYear: 2026,
      toYear: 2026,
    );
    const spring = PassTerm(
      duration: TermDuration.semester,
      season: TermSeason.spring,
      fromYear: 2027,
      toYear: 2027,
    );
    const year = PassTerm(
      duration: TermDuration.year,
      fromYear: 2026,
      toYear: 2027,
    );
    const three = PassTerm(
      duration: TermDuration.threeYears,
      fromYear: 2026,
      toYear: 2029,
    );
    expect(fall.label(spring: 'Vår', fall: 'Høst'), 'Høst 2026');
    expect(spring.label(spring: 'Spring', fall: 'Fall'), 'Spring 2027');
    expect(year.label(spring: 'Spring', fall: 'Fall'), '2026–2027');
    expect(three.label(spring: 'Spring', fall: 'Fall'), '2026–2029');
    expect(PassTerm.tryParse(null), isNull);
    expect(
      PassTerm.tryParse({
        'duration': 'three_years',
        'fromYear': 2026,
        'toYear': 2029,
      }),
      three,
    );
  });

  test('a code never appears in toString', () {
    const code = PassCode(slot: 1, code: 'v1.secret-user.1.sig');
    expect(code.toString(), isNot(contains('secret')));
    final pass = MemberPassResponse.fromJson(activeJson());
    expect(pass.toString(), isNot(contains('v1.')));
  });

  test('an invalid day color hex falls back to grey', () {
    expect(
      DayColor.fromJson({'name': 'teal', 'hex': 'nope'}).color,
      const Color(0xFF8E8E93),
    );
    expect(DayColor.names, hasLength(12));
  });

  test('parses scanner access', () {
    final access = ScannerAccess.fromJson({
      'campusId': null,
      'expiresAt': '2026-09-20T22:00:00.000Z',
      'dayColor': {'name': 'blue', 'hex': '#0090FF'},
    });
    expect(access.campusId, isNull);
    expect(access.expiresAt, DateTime.utc(2026, 9, 20, 22));
    expect(access.dayColor.name, 'blue');
  });

  test('parses every scan result and reason', () {
    expect(
      ScanOutcome.fromJson({
        'result': 'valid',
        'name': 'Kari',
        'membershipName': 'Year',
        'expiryDate': '2027-06-30',
      }),
      ScanOutcome(
        result: ScanResult.valid,
        name: 'Kari',
        membershipName: 'Year',
        expiryDate: DateTime(2027, 6, 30),
      ),
    );
    expect(
      ScanOutcome.fromJson({
        'result': 'duplicate',
        'secondsSincePrevious': 42,
      }).secondsSincePrevious,
      42,
    );
    expect(
      ScanOutcome.fromJson({'result': 'check_id'}).result,
      ScanResult.checkId,
    );
    for (final (value, reason) in [
      ('bad_code', DenyReason.badCode),
      ('stale', DenyReason.stale),
      ('expired', DenyReason.expired),
      ('not_member', DenyReason.notMember),
      ('not_linked', DenyReason.notLinked),
      ('new_reason', DenyReason.other),
    ]) {
      final outcome = ScanOutcome.fromJson({
        'result': 'denied',
        'reason': value,
      });
      expect(outcome.result, ScanResult.denied);
      expect(outcome.reason, reason);
    }
    expect(
      ScanOutcome.fromJson({'result': 'what'}).result,
      ScanResult.unavailable,
    );
    expect(
      ScanOutcome.fromJson({'result': 'valid', 'reason': 'stale'}).reason,
      isNull,
    );
  });
}
