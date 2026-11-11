import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/member_pass.dart';
import '../member_pass/member_pass_provider.dart';
import '../member_pass/member_pass_session.dart';
import '../membership/membership_overview_provider.dart';

/// Where the student stands, as far as benefits are concerned.
enum BenefitStanding {
  member,
  upcoming,
  needsBi,
  notMember,
  signedOut,

  /// Still finding out. Never shown as "not a member".
  checking,

  /// The membership could not be checked. Never shown as "not a member".
  unavailable,
}

class BenefitStandingInfo extends Equatable {
  const BenefitStandingInfo(
    this.standing, {
    this.validUntil,
    this.upcomingStart,
  });

  final BenefitStanding standing;
  final DateTime? validUntil;
  final DateTime? upcomingStart;

  bool get isNonMember =>
      standing == BenefitStanding.notMember ||
      standing == BenefitStanding.signedOut;

  @override
  List<Object?> get props => [standing, validUntil, upcomingStart];
}

BenefitStandingInfo benefitStandingFrom(
  MemberPassView view, {
  DateTime? upcomingStart,
  bool overviewPending = false,
}) => switch (view.status) {
  PassStatus.active => BenefitStandingInfo(
    BenefitStanding.member,
    validUntil: view.pass?.holder.expiryDate,
  ),
  PassStatus.signedOut => const BenefitStandingInfo(BenefitStanding.signedOut),
  PassStatus.loading => const BenefitStandingInfo(BenefitStanding.checking),
  PassStatus.reconnect => const BenefitStandingInfo(
    BenefitStanding.unavailable,
  ),
  PassStatus.noPass => switch (view.noPassState) {
    NoPassState.noBiIdentity => const BenefitStandingInfo(
      BenefitStanding.needsBi,
    ),
    // The overview may still reveal a paid membership that starts later, so
    // "not a member" waits for it.
    NoPassState.notMember || NoPassState.expired
        when overviewPending && upcomingStart == null =>
      const BenefitStandingInfo(BenefitStanding.checking),
    NoPassState.notMember || NoPassState.expired =>
      upcomingStart == null
          ? const BenefitStandingInfo(BenefitStanding.notMember)
          : BenefitStandingInfo(
              BenefitStanding.upcoming,
              upcomingStart: upcomingStart,
            ),
    NoPassState.unavailable ||
    null => const BenefitStandingInfo(BenefitStanding.unavailable),
  },
};

/// The standing for the whole benefits feature. The `select` keeps the pass's
/// one-second ticker from rebuilding watchers.
final benefitStandingProvider = Provider.autoDispose<BenefitStandingInfo>((
  ref,
) {
  // A reload (the account changed: a sign-in, or a BI sign-in into another
  // account) still carries the previous account's answer, so it counts as
  // nothing yet. A pull-to-refresh (`isRefreshing`) keeps the current one.
  final start = ref.watch(
    membershipOverviewProvider.select(
      (o) =>
          o.isReloading ? null : o.value?.upcomingMembership?.startDate,
    ),
  );
  // Loading with nothing to show yet for this account. An error falls back
  // to the pass.
  final pending = ref.watch(
    membershipOverviewProvider.select(
      (o) => o.isLoading && (!o.hasValue || o.isReloading),
    ),
  );
  return ref.watch(
    memberPassProvider.select(
      (v) => benefitStandingFrom(
        v,
        upcomingStart: start,
        overviewPending: pending,
      ),
    ),
  );
});
