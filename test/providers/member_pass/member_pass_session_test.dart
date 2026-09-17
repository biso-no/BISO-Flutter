import 'package:biso/data/models/member_pass.dart';
import 'package:biso/providers/member_pass/member_pass_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_member_pass_api.dart';

void main() {
  // A slot boundary, so slot arithmetic is easy to read.
  final t0 = DateTime.utc(2026, 9, 17, 10).millisecondsSinceEpoch;

  MemberPassSession activeSession({
    int localNow = 0,
    int serverNow = 0,
    int count = 20,
  }) {
    return MemberPassSession()
      ..apply(activePassAt(serverNow, count: count), localNow);
  }

  test('starts loading with nothing to show', () {
    final session = MemberPassSession();
    expect(session.status, PassStatus.loading);
    expect(session.view(t0).code, isNull);
  });

  test('shows the code for the current slot', () {
    final session = activeSession(localNow: t0, serverNow: t0);
    final slot = t0 ~/ passSlotMs;
    expect(session.current(t0)!.slot, slot);
    expect(session.current(t0 + 29999)!.slot, slot);
    expect(session.current(t0 + 30000)!.slot, slot + 1);
    expect(session.msUntilNextSlot(t0), 30000);
    expect(session.msUntilNextSlot(t0 + 29999), 1);
  });

  test('applies positive drift when the phone is behind', () {
    // Phone reads 45 s earlier than the server.
    final session = activeSession(localNow: t0 - 45000, serverNow: t0);
    expect(session.drift, 45000);
    expect(session.current(t0 - 45000)!.slot, t0 ~/ passSlotMs);
    expect(session.msUntilNextSlot(t0 - 45000), 30000);
  });

  test('applies negative drift when the phone is ahead', () {
    final session = activeSession(localNow: t0 + 70000, serverNow: t0);
    expect(session.drift, -70000);
    expect(session.current(t0 + 70000)!.slot, t0 ~/ passSlotMs);
    expect(
      session.view(t0 + 70000).serverTime,
      DateTime.fromMillisecondsSinceEpoch(t0, isUtc: true),
    );
  });

  test('needs a refetch when fewer than 4 codes remain', () {
    final session = activeSession(localNow: t0, serverNow: t0, count: 5);
    expect(session.remainingCodes(t0), 5);
    expect(session.needsRefetch(t0), isFalse);
    expect(session.needsRefetch(t0 + passSlotMs), isFalse); // 4 left
    expect(session.needsRefetch(t0 + 2 * passSlotMs), isTrue); // 3 left
  });

  test('a clock before the first code has no code and needs a refetch', () {
    final session = activeSession(localNow: t0, serverNow: t0);
    final before = t0 - 5 * passSlotMs;
    expect(session.current(before), isNull);
    expect(session.needsRefetch(before), isTrue);
    expect(session.view(before).status, PassStatus.active);
    expect(session.view(before).code, isNull);
  });

  test('retries at most every 15 s, never while a fetch is in flight', () {
    final session = activeSession(localNow: t0, serverNow: t0, count: 3);
    expect(
      session.shouldRetry(t0, lastAttemptMs: null, inFlight: false),
      isTrue,
    );
    expect(
      session.shouldRetry(t0, lastAttemptMs: null, inFlight: true),
      isFalse,
    );
    expect(
      session.shouldRetry(t0 + 14999, lastAttemptMs: t0, inFlight: false),
      isFalse,
    );
    expect(
      session.shouldRetry(t0 + 15000, lastAttemptMs: t0, inFlight: false),
      isTrue,
    );
  });

  test('does not retry a healthy pass', () {
    final session = activeSession(localNow: t0, serverNow: t0);
    expect(
      session.shouldRetry(t0 + 60000, lastAttemptMs: t0, inFlight: false),
      isFalse,
    );
  });

  test('a network failure keeps a pass with no current code but future codes, '
      'offline and still active', () {
    // firstSlotOffset: 1 means both codes are for slots after the current
    // one, so current(t0) is null but hasUsableCode(t0) is true — the case
    // "usable" must mean "a code at or after now", not "a code for now".
    final session = MemberPassSession()
      ..apply(activePassAt(t0, count: 2, firstSlotOffset: 1), t0);
    expect(session.current(t0), isNull);
    expect(session.hasUsableCode(t0), isTrue);

    session.applyNetworkFailure(t0);

    expect(session.status, PassStatus.active);
    expect(session.offline, isTrue);
    expect(session.hasUsableCode(t0), isTrue);
    expect(session.view(t0).code, isNull);
    expect(session.view(t0).pass, isNotNull);
  });

  test('a server failure keeps a pass with no current code but future codes, '
      'without setting offline', () {
    final session = MemberPassSession()
      ..apply(activePassAt(t0, count: 2, firstSlotOffset: 1), t0);
    expect(session.current(t0), isNull);
    expect(session.hasUsableCode(t0), isTrue);

    session.applyServerFailure(t0);

    expect(session.status, PassStatus.active);
    expect(session.offline, isFalse);
    expect(session.view(t0).code, isNull);
    expect(session.view(t0).pass, isNotNull);
  });

  test('a network failure with no usable code asks to reconnect', () {
    final session = activeSession(localNow: t0, serverNow: t0, count: 2);
    expect(session.hasUsableCode(t0 + 3 * passSlotMs), isFalse);
    session.applyNetworkFailure(t0 + 3 * passSlotMs);
    expect(session.status, PassStatus.reconnect);
    expect(session.pass, isNull);
    expect(session.offline, isTrue);
    expect(
      session.shouldRetry(
        t0 + 4 * passSlotMs,
        lastAttemptMs: t0,
        inFlight: false,
      ),
      isTrue,
    );
  });

  test('a network failure keeps noPass, with offline set', () {
    final session = MemberPassSession()
      ..apply(const NoPass(NoPassState.notMember), t0)
      ..applyNetworkFailure(t0 + 1000);
    expect(session.status, PassStatus.noPass);
    expect(session.noPassState, NoPassState.notMember);
    expect(session.offline, isTrue);
  });

  test('a first fetch that fails on the network asks to reconnect', () {
    final session = MemberPassSession()..applyNetworkFailure(t0);
    expect(session.status, PassStatus.reconnect);
    expect(session.offline, isTrue);
  });

  test('a later success clears offline', () {
    final session = activeSession(localNow: t0, serverNow: t0)
      ..applyNetworkFailure(t0);
    session.apply(activePassAt(t0 + 1000), t0 + 1000);
    expect(session.offline, isFalse);
  });

  test('a server failure keeps a usable pass without setting offline', () {
    final session = activeSession(localNow: t0, serverNow: t0);
    session.applyServerFailure(t0 + 1000);
    expect(session.status, PassStatus.active);
    expect(session.offline, isFalse);
    expect(session.view(t0 + 1000).code, isNotNull);
  });

  test('a server failure with no usable code shows NoPass(unavailable), '
      'offline false', () {
    final session = activeSession(localNow: t0, serverNow: t0, count: 2);
    session.applyServerFailure(t0 + 3 * passSlotMs);
    expect(session.status, PassStatus.noPass);
    expect(session.noPassState, NoPassState.unavailable);
    expect(session.pass, isNull);
    expect(session.offline, isFalse);
  });

  test('a server failure turns noPass(notMember) into unavailable', () {
    final session = MemberPassSession()
      ..apply(const NoPass(NoPassState.notMember), t0)
      ..applyServerFailure(t0 + 1000);
    expect(session.status, PassStatus.noPass);
    expect(session.noPassState, NoPassState.unavailable);
    expect(session.offline, isFalse);
  });

  test('a server failure while loading shows unavailable', () {
    final session = MemberPassSession()..applyServerFailure(t0);
    expect(session.status, PassStatus.noPass);
    expect(session.noPassState, NoPassState.unavailable);
    expect(session.offline, isFalse);
  });

  test(
    'a server failure keeps offline unchanged when it was already offline',
    () {
      final session = activeSession(localNow: t0, serverNow: t0)
        ..applyNetworkFailure(t0)
        ..applyServerFailure(t0 + 1000);
      expect(session.status, PassStatus.active);
      expect(session.offline, isTrue);
    },
  );

  test('a 401 clears the pass', () {
    final session = activeSession(localNow: t0, serverNow: t0)
      ..applyUnauthorized();
    expect(session.status, PassStatus.signedOut);
    expect(session.pass, isNull);
    expect(session.view(t0).code, isNull);
  });

  test('a 200 without a pass replaces an active pass', () {
    final session = activeSession(localNow: t0, serverNow: t0)
      ..apply(const NoPass(NoPassState.expired), t0);
    expect(session.status, PassStatus.noPass);
    expect(session.noPassState, NoPassState.expired);
    expect(session.pass, isNull);
  });

  test('the view never prints the code', () {
    final session = activeSession(localNow: t0, serverNow: t0);
    expect(session.view(t0).toString(), isNot(contains('v1.')));
  });
}
