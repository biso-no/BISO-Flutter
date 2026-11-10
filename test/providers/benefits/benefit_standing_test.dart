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
import '../../helpers/membership_fixtures.dart';

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

  group('when the account changes', () {
    // Spring 2027: a paid membership that has not started yet.
    final paidLater = membershipOverviewOf(upcoming: [spring2027Semester]);
    final laterStart = spring2027Semester.startDate;

    final before = <String, (String?, MembershipOverview?)>{
      'signed out': (null, null),
      'another account that starts later': ('u0', paidLater),
    };
    for (final MapEntry(key: name, value: (from, answer)) in before.entries) {
      test('from $name: checking while the new overview loads, never the '
          'old answer', () async {
        final accounts = _Accounts({from: Completer()..complete(answer)});
        final (container, sub) = _standing(accounts, signedIn: from);
        await container.read(membershipOverviewProvider.future);

        accounts.answers['u1'] = Completer();
        container.read(_signedIn.notifier).state = 'u1';
        await container.pump();
        expect(sub.read().standing, BenefitStanding.checking);
      });
    }

    test('settles on the new account\'s later start', () async {
      final accounts = _Accounts({null: Completer()..complete(null)});
      final (container, sub) = _standing(accounts, signedIn: null);
      await container.read(membershipOverviewProvider.future);

      final next = accounts.answers['u1'] = Completer();
      container.read(_signedIn.notifier).state = 'u1';
      await container.pump();
      expect(sub.read().standing, BenefitStanding.checking);

      next.complete(paidLater);
      await container.read(membershipOverviewProvider.future);
      expect(
        sub.read(),
        BenefitStandingInfo(
          BenefitStanding.upcoming,
          upcomingStart: laterStart,
        ),
      );
    });

    test('a failed overview with no answer falls back to the pass', () async {
      final accounts = _Accounts({
        'u1': Completer()..completeError(Exception('offline')),
      });
      final (container, sub) = _standing(accounts, signedIn: 'u1');
      await expectLater(
        container.read(membershipOverviewProvider.future),
        throwsException,
      );
      expect(sub.read().standing, BenefitStanding.notMember);
    });

    test('a pull-to-refresh keeps the current answer', () async {
      final accounts = _Accounts({'u1': Completer()..complete(paidLater)});
      final (container, sub) = _standing(accounts, signedIn: 'u1');
      await container.read(membershipOverviewProvider.future);
      expect(sub.read().standing, BenefitStanding.upcoming);

      final again = Completer<MembershipOverview?>();
      accounts.refreshes.add(again);
      final refresh = container
          .read(membershipOverviewProvider.notifier)
          .refresh();
      await container.pump();
      expect(container.read(membershipOverviewProvider).isRefreshing, isTrue);
      expect(sub.read().standing, BenefitStanding.upcoming);
      again.complete(paidLater);
      await refresh;
      expect(sub.read().standing, BenefitStanding.upcoming);
    });
  });
}

/// The signed-in account, which [membershipUserIdProvider] follows.
final _signedIn = StateProvider<String?>((_) => null);

/// What each account's overview answers, and the answer for each refresh.
class _Accounts {
  _Accounts(this.answers);
  final Map<String?, Completer<MembershipOverview?>> answers;
  final refreshes = <Completer<MembershipOverview?>>[];
}

/// The standing for a student whose pass says notMember, with an overview
/// that loads per account, as the app's does.
(ProviderContainer, ProviderSubscription<BenefitStandingInfo>) _standing(
  _Accounts accounts, {
  required String? signedIn,
}) {
  final container = ProviderContainer(
    overrides: [
      _signedIn.overrideWith((_) => signedIn),
      membershipUserIdProvider.overrideWith((ref) => ref.watch(_signedIn)),
      memberPassProvider.overrideWith(
        () => FixedMemberPass(
          const MemberPassView(
            status: PassStatus.noPass,
            noPassState: NoPassState.notMember,
          ),
        ),
      ),
      membershipOverviewProvider.overrideWith(() => _AccountOverview(accounts)),
    ],
  );
  addTearDown(container.dispose);
  final sub = container.listen(benefitStandingProvider, (_, _) {});
  addTearDown(sub.close);
  return (container, sub);
}

/// Rebuilds when the account changes, as the app's overview does; a refresh
/// keeps the current answer while it reloads.
class _AccountOverview extends MembershipOverviewNotifier {
  _AccountOverview(this.accounts);
  final _Accounts accounts;

  @override
  Future<MembershipOverview?> build() =>
      accounts.answers[ref.watch(membershipUserIdProvider)]!.future;

  @override
  Future<void> refresh({bool force = true}) async {
    state = const AsyncLoading<MembershipOverview?>().copyWithPrevious(state);
    state = await AsyncValue.guard(() => accounts.refreshes.removeAt(0).future);
  }
}

class _PendingOverview extends MembershipOverviewNotifier {
  _PendingOverview(this.completer);
  final Completer<MembershipOverview?> completer;

  @override
  Future<MembershipOverview?> build() => completer.future;
}
