import 'package:biso/data/models/member_pass.dart';
import 'package:biso/providers/benefits/benefit_standing.dart';
import 'package:biso/providers/member_pass/member_pass_session.dart';
import 'dart:async';

import 'package:biso/providers/member_pass/member_pass_provider.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:biso/data/models/membership_overview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  final cases = <String, (MemberPassView, DateTime?, bool, BenefitStanding)>{
    'signedOut': (
      const MemberPassView(status: PassStatus.signedOut),
      null,
      false,
      BenefitStanding.signedOut,
    ),
    'loading': (
      const MemberPassView(status: PassStatus.loading),
      null,
      false,
      BenefitStanding.checking,
    ),
    'reconnect': (
      const MemberPassView(status: PassStatus.reconnect),
      null,
      false,
      BenefitStanding.unavailable,
    ),
    'noBiIdentity': (
      const MemberPassView(
        status: PassStatus.noPass,
        noPassState: NoPassState.noBiIdentity,
      ),
      null,
      false,
      BenefitStanding.needsBi,
    ),
    'notMember': (
      const MemberPassView(
        status: PassStatus.noPass,
        noPassState: NoPassState.notMember,
      ),
      null,
      false,
      BenefitStanding.notMember,
    ),
    'expired': (
      const MemberPassView(
        status: PassStatus.noPass,
        noPassState: NoPassState.expired,
      ),
      null,
      false,
      BenefitStanding.notMember,
    ),
    'notMember with upcoming': (
      const MemberPassView(
        status: PassStatus.noPass,
        noPassState: NoPassState.notMember,
      ),
      upcoming,
      false,
      BenefitStanding.upcoming,
    ),
    'unavailable': (
      const MemberPassView(
        status: PassStatus.noPass,
        noPassState: NoPassState.unavailable,
      ),
      null,
      false,
      BenefitStanding.unavailable,
    ),
    'noPass without state': (
      const MemberPassView(status: PassStatus.noPass),
      null,
      false,
      BenefitStanding.unavailable,
    ),
    'expired with upcoming': (
      const MemberPassView(
        status: PassStatus.noPass,
        noPassState: NoPassState.expired,
      ),
      upcoming,
      false,
      BenefitStanding.upcoming,
    ),
    'notMember, overview pending': (
      const MemberPassView(
        status: PassStatus.noPass,
        noPassState: NoPassState.notMember,
      ),
      null,
      true,
      BenefitStanding.checking,
    ),
    'expired, overview pending': (
      const MemberPassView(
        status: PassStatus.noPass,
        noPassState: NoPassState.expired,
      ),
      null,
      true,
      BenefitStanding.checking,
    ),
    'noBiIdentity, overview pending': (
      const MemberPassView(
        status: PassStatus.noPass,
        noPassState: NoPassState.noBiIdentity,
      ),
      null,
      true,
      BenefitStanding.needsBi,
    ),
    'active, overview pending': (
      activeView(),
      null,
      true,
      BenefitStanding.member,
    ),
  };

  for (final entry in cases.entries) {
    test('maps ${entry.key}', () {
      final (view, start, pending, expected) = entry.value;
      final info = benefitStandingFrom(
        view,
        upcomingStart: start,
        overviewPending: pending,
      );
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

  test('a notMember pass waits for the overview before saying so', () async {
    final completer = Completer<MembershipOverview?>();
    final container = ProviderContainer(
      overrides: [
        memberPassProvider.overrideWith(
          () => FixedMemberPass(
            const MemberPassView(
              status: PassStatus.noPass,
              noPassState: NoPassState.notMember,
            ),
          ),
        ),
        membershipOverviewProvider.overrideWith(
          () => _PendingOverview(completer),
        ),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(benefitStandingProvider, (_, _) {});
    addTearDown(sub.close);

    expect(sub.read().standing, BenefitStanding.checking);
    completer.complete(null);
    await container.read(membershipOverviewProvider.future);
    expect(sub.read().standing, BenefitStanding.notMember);
  });
}

class _PendingOverview extends MembershipOverviewNotifier {
  _PendingOverview(this.completer);
  final Completer<MembershipOverview?> completer;

  @override
  Future<MembershipOverview?> build() => completer.future;
}
