import 'package:equatable/equatable.dart';

import '../../data/models/member_pass.dart';

/// Pass codes rotate every 30 seconds.
const passSlotMs = 30000;

/// Fetch more codes when fewer than this many remain.
const passRefetchBelow = 4;

/// While offline or low on codes, try again this often.
const passRetryEveryMs = 15000;

enum PassStatus { loading, active, noPass, reconnect, signedOut }

/// What the pass screen shows at one instant.
class MemberPassView extends Equatable {
  const MemberPassView({
    required this.status,
    this.noPassState,
    this.pass,
    this.code,
    this.msUntilNextSlot = 0,
    this.offline = false,
    this.fetching = false,
    this.serverTime,
  });

  final PassStatus status;
  final NoPassState? noPassState;
  final ActivePass? pass;

  /// The raw code for the QR, or null when none is valid right now.
  final String? code;
  final int msUntilNextSlot;
  final bool offline;
  final bool fetching;

  /// The server's clock now, in UTC.
  final DateTime? serverTime;

  @override
  List<Object?> get props => [
    status,
    noPassState,
    pass,
    code,
    msUntilNextSlot,
    offline,
    fetching,
    serverTime,
  ];

  @override
  bool? get stringify => false;

  @override
  String toString() => 'MemberPassView($status, offline: $offline)';
}

/// The client rules for a live pass, mirroring the web `pass-refresh.ts`.
/// It holds no timers and takes the local clock as an argument.
class MemberPassSession {
  PassStatus _status = PassStatus.loading;
  NoPassState? _noPassState;
  ActivePass? _pass;
  int _drift = 0;
  bool _offline = false;

  PassStatus get status => _status;
  NoPassState? get noPassState => _noPassState;
  ActivePass? get pass => _pass;
  bool get offline => _offline;

  /// Server clock minus local clock, in milliseconds.
  int get drift => _drift;

  /// A 200 answer replaces whatever is shown.
  void apply(MemberPassResponse response, int localNowMs) {
    _offline = false;
    switch (response) {
      case ActivePass():
        _status = PassStatus.active;
        _noPassState = null;
        _pass = response;
        _drift = response.serverNow - localNowMs;
      case NoPass(:final state):
        _status = PassStatus.noPass;
        _noPassState = state;
        _pass = null;
    }
  }

  /// A 401 replaces whatever is shown.
  void applyUnauthorized() {
    _status = PassStatus.signedOut;
    _noPassState = null;
    _pass = null;
    _offline = false;
  }

  /// A 5xx or network failure keeps a pass that can still be shown.
  void applyTransientFailure(int nowMs) {
    _offline = true;
    if (_status == PassStatus.active && current(nowMs) != null) return;
    if (_status == PassStatus.noPass || _status == PassStatus.signedOut) {
      return;
    }
    _status = PassStatus.reconnect;
    _pass = null;
  }

  int slotAt(int nowMs) => (nowMs + _drift) ~/ passSlotMs;

  PassCode? current(int nowMs) {
    final pass = _pass;
    if (pass == null) return null;
    final slot = slotAt(nowMs);
    for (final code in pass.codes) {
      if (code.slot == slot) return code;
    }
    return null;
  }

  int msUntilNextSlot(int nowMs) => passSlotMs - (nowMs + _drift) % passSlotMs;

  int remainingCodes(int nowMs) {
    final pass = _pass;
    if (pass == null) return 0;
    final slot = slotAt(nowMs);
    return pass.codes.where((code) => code.slot >= slot).length;
  }

  bool needsRefetch(int nowMs) =>
      _status == PassStatus.active &&
      (remainingCodes(nowMs) < passRefetchBelow || current(nowMs) == null);

  bool shouldRetry(
    int nowMs, {
    required int? lastAttemptMs,
    required bool inFlight,
  }) {
    if (inFlight) return false;
    if (!_offline && !needsRefetch(nowMs)) return false;
    return lastAttemptMs == null || nowMs - lastAttemptMs >= passRetryEveryMs;
  }

  MemberPassView view(int nowMs, {bool fetching = false}) {
    final active = _status == PassStatus.active;
    return MemberPassView(
      status: _status,
      noPassState: _noPassState,
      pass: _pass,
      code: current(nowMs)?.code,
      msUntilNextSlot: active ? msUntilNextSlot(nowMs) : 0,
      offline: _offline,
      fetching: fetching,
      serverTime: active
          ? DateTime.fromMillisecondsSinceEpoch(nowMs + _drift, isUtc: true)
          : null,
    );
  }
}
