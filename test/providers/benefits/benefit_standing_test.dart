import 'package:biso/data/models/member_pass.dart';
import 'package:biso/providers/benefits/benefit_standing.dart';
import 'package:biso/providers/member_pass/member_pass_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_member_pass_api.dart';

void main() {
  final upcoming = DateTime.utc(2027, 1, 1);

  test('an active pass is a member, valid until the holder expiry', () {
    final view = activeView();
    final info = benefitStandingFrom(view);
    expect(info.standing, BenefitStanding.member);
    expect(info.validUntil, view.pass!.holder.expiryDate);
  });

  final cases = <String, (MemberPassView, DateTime?, BenefitStanding)>{
    'signedOut': (
      const MemberPassView(status: PassStatus.signedOut),
      null,
      BenefitStanding.signedOut,
    ),
    'loading': (
      const MemberPassView(status: PassStatus.loading),
      null,
      BenefitStanding.checking,
    ),
    'reconnect': (
      const MemberPassView(status: PassStatus.reconnect),
      null,
      BenefitStanding.unavailable,
    ),
    'noBiIdentity': (
      const MemberPassView(
        status: PassStatus.noPass,
        noPassState: NoPassState.noBiIdentity,
      ),
      null,
      BenefitStanding.needsBi,
    ),
    'notMember': (
      const MemberPassView(
        status: PassStatus.noPass,
        noPassState: NoPassState.notMember,
      ),
      null,
      BenefitStanding.notMember,
    ),
    'expired': (
      const MemberPassView(
        status: PassStatus.noPass,
        noPassState: NoPassState.expired,
      ),
      null,
      BenefitStanding.notMember,
    ),
    'notMember with upcoming': (
      const MemberPassView(
        status: PassStatus.noPass,
        noPassState: NoPassState.notMember,
      ),
      upcoming,
      BenefitStanding.upcoming,
    ),
    'unavailable': (
      const MemberPassView(
        status: PassStatus.noPass,
        noPassState: NoPassState.unavailable,
      ),
      null,
      BenefitStanding.unavailable,
    ),
    'noPass without state': (
      const MemberPassView(status: PassStatus.noPass),
      null,
      BenefitStanding.unavailable,
    ),
  };

  for (final entry in cases.entries) {
    test('maps ${entry.key}', () {
      final (view, start, expected) = entry.value;
      final info = benefitStandingFrom(view, upcomingStart: start);
      expect(info.standing, expected);
      if (expected == BenefitStanding.upcoming) {
        expect(info.upcomingStart, start);
      }
    });
  }

  test('isNonMember is true only for notMember and signedOut', () {
    for (final standing in BenefitStanding.values) {
      expect(
        BenefitStandingInfo(standing).isNonMember,
        standing == BenefitStanding.notMember ||
            standing == BenefitStanding.signedOut,
      );
    }
  });
}
