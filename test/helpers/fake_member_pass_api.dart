import 'dart:async';
import 'dart:typed_data';

import 'package:biso/data/models/member_pass.dart';
import 'package:biso/data/services/member_pass_api_client.dart';
import 'package:biso/data/services/scanner_camera.dart';
import 'package:biso/data/services/screen_presentation.dart';
import 'package:biso/providers/member_pass/member_pass_provider.dart';
import 'package:biso/providers/member_pass/member_pass_session.dart';
import 'package:biso/providers/member_pass/scanner_access_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const testDayColor = DayColor(name: 'teal', hex: '#12A594');

const testTerm = PassTerm(
  duration: TermDuration.semester,
  season: TermSeason.fall,
  fromYear: 2026,
  toYear: 2026,
);

/// An active pass whose first code is for the slot containing
/// [serverNowMs] (shifted by [firstSlotOffset]).
ActivePass activePassAt(
  int serverNowMs, {
  int count = 20,
  int firstSlotOffset = 0,
  WalletAvailability wallets = const WalletAvailability(
    apple: true,
    google: true,
  ),
  PassTerm? term = testTerm,
}) {
  final first = serverNowMs ~/ 30000 + firstSlotOffset;
  return ActivePass(
    holder: PassHolder(
      name: 'Kari Nordmann',
      membershipName: 'Semester',
      startDate: DateTime(2026, 7, 1),
      expiryDate: DateTime(2026, 12, 31),
      term: term,
    ),
    codes: [
      for (var i = 0; i < count; i++)
        PassCode(slot: first + i, code: 'v1.user-1.${first + i}.sig'),
    ],
    dayColor: testDayColor,
    serverNow: serverNowMs,
    wallets: wallets,
  );
}

Never _unset(String name) =>
    throw StateError('FakeMemberPassApi.$name was not set');

/// A [MemberPassApi] whose answers each test sets.
class FakeMemberPassApi implements MemberPassApi {
  FutureOr<MemberPassResponse> Function() onFetchPass = () =>
      _unset('onFetchPass');
  FutureOr<Uint8List> Function() onFetchApplePass = () =>
      _unset('onFetchApplePass');
  FutureOr<Uri> Function() onFetchGoogleSaveUrl = () =>
      _unset('onFetchGoogleSaveUrl');
  FutureOr<ScannerAccess> Function() onFetchScannerAccess = () =>
      _unset('onFetchScannerAccess');
  FutureOr<ScanOutcome> Function(String code) onScan = (_) => _unset('onScan');

  int fetchPassCalls = 0;
  int applePassCalls = 0;
  int googleSaveUrlCalls = 0;
  int scannerAccessCalls = 0;
  final scanned = <String>[];

  @override
  Future<MemberPassResponse> fetchPass() async {
    fetchPassCalls++;
    return onFetchPass();
  }

  @override
  Future<Uint8List> fetchApplePass() async {
    applePassCalls++;
    return onFetchApplePass();
  }

  @override
  Future<Uri> fetchGoogleSaveUrl() async {
    googleSaveUrlCalls++;
    return onFetchGoogleSaveUrl();
  }

  @override
  Future<ScannerAccess> fetchScannerAccess() async {
    scannerAccessCalls++;
    return onFetchScannerAccess();
  }

  @override
  Future<ScanOutcome> scan(String code) async {
    scanned.add(code);
    return onScan(code);
  }
}

/// A scanner access answer that never touches the network. A null value
/// stays loading forever.
class FixedScannerAccess extends ScannerAccessNotifier {
  FixedScannerAccess(this.value);

  final ScannerAccessState? value;
  int freshCalls = 0;
  int builds = 0;

  @override
  Future<ScannerAccessState> build() {
    builds++;
    final value = this.value;
    return value == null
        ? Completer<ScannerAccessState>().future
        : Future.value(value);
  }

  @override
  Future<void> ensureFresh({bool force = false}) async => freshCalls++;
}

const grantedAccess = ScannerGranted(ScannerAccess(dayColor: testDayColor));

/// 10:00:00 UTC on 17 September 2026, the moment test passes are made for.
final testPassNow = DateTime.utc(2026, 9, 17, 10).millisecondsSinceEpoch;

MemberPassView activeView({
  bool offline = false,
  WalletAvailability wallets = const WalletAvailability(
    apple: true,
    google: true,
  ),
}) {
  final session = MemberPassSession()
    ..apply(activePassAt(testPassNow, wallets: wallets), testPassNow);
  if (offline) session.applyTransientFailure(testPassNow);
  return session.view(testPassNow);
}

/// A pass notifier that shows [view] and never starts timers or fetches.
class FixedMemberPass extends MemberPassNotifier {
  FixedMemberPass(this.view);

  final MemberPassView view;
  int retries = 0;
  int holds = 0;

  @override
  MemberPassView build() => view;

  @override
  Future<void> retry() async => retries++;

  @override
  KeepAliveLink hold() {
    holds++;
    return super.hold();
  }
}

class FakeScreenPresentation implements ScreenPresentation {
  int enters = 0;
  int exits = 0;

  /// Every call in the order it started.
  final List<String> calls = [];

  /// When set, each call waits for its completer in [pendingCalls].
  bool deferCalls = false;
  final List<Completer<void>> pendingCalls = [];

  /// The most calls that were ever running at once.
  int maxConcurrent = 0;
  int _running = 0;

  @override
  Future<void> enter() {
    enters++;
    return _record('enter');
  }

  @override
  Future<void> exit() {
    exits++;
    return _record('exit');
  }

  Future<void> _record(String name) async {
    calls.add(name);
    _running++;
    if (_running > maxConcurrent) maxConcurrent = _running;
    try {
      if (deferCalls) {
        final completer = Completer<void>();
        pendingCalls.add(completer);
        await completer.future;
      }
    } finally {
      _running--;
    }
  }
}

/// A camera that shows a placeholder and reads whatever the test says.
class FakeScannerCamera implements ScannerCamera {
  void Function(String code)? _onCode;
  int pauses = 0;
  int resumes = 0;
  int stops = 0;
  bool disposed = false;

  void read(String code) => _onCode!(code);

  @override
  Widget preview({
    required void Function(String code) onCode,
    required WidgetBuilder onError,
  }) {
    _onCode = onCode;
    return const SizedBox.expand(key: Key('fake-camera'));
  }

  @override
  Future<void> pause() async => pauses++;

  @override
  Future<void> resume() async => resumes++;

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async => disposed = true;
}
