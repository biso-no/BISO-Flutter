import 'dart:ui' show Color;

import 'package:equatable/equatable.dart';

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());

int? _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('${value ?? ''}');

String? _text(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

/// Why there is no pass to show. The server decides it.
enum NoPassState {
  noBiIdentity('no_bi_identity'),
  notMember('not_member'),
  expired('expired'),
  unavailable('unavailable');

  const NoPassState(this.value);

  final String value;

  /// An unknown state reads as "cannot tell right now".
  static NoPassState fromValue(String? value) {
    for (final state in values) {
      if (state.value == value) return state;
    }
    return unavailable;
  }
}

enum TermDuration { semester, year, threeYears }

enum TermSeason { spring, fall }

/// The period a membership covers, for the pass label.
class PassTerm extends Equatable {
  const PassTerm({
    required this.duration,
    this.season,
    required this.fromYear,
    required this.toYear,
  });

  final TermDuration duration;
  final TermSeason? season;
  final int fromYear;
  final int toYear;

  static PassTerm? tryParse(Object? json) {
    if (json is! Map) return null;
    final duration = switch (json['duration']) {
      'semester' => TermDuration.semester,
      'year' => TermDuration.year,
      'three_years' => TermDuration.threeYears,
      _ => null,
    };
    final from = _int(json['fromYear']);
    final to = _int(json['toYear']);
    if (duration == null || from == null || to == null) return null;
    final season = switch (json['season']) {
      'spring' => TermSeason.spring,
      'fall' => TermSeason.fall,
      _ => null,
    };
    return PassTerm(
      duration: duration,
      season: season,
      fromYear: from,
      toYear: to,
    );
  }

  /// "Fall 2026" for a semester, otherwise "2026–2027" (or "2026").
  String label({required String spring, required String fall}) {
    final season = this.season;
    if (duration == TermDuration.semester && season != null) {
      return '${season == TermSeason.spring ? spring : fall} $fromYear';
    }
    return fromYear == toYear ? '$fromYear' : '$fromYear–$toYear';
  }

  @override
  List<Object?> get props => [duration, season, fromYear, toYear];
}

class PassHolder extends Equatable {
  const PassHolder({
    required this.name,
    required this.membershipName,
    this.startDate,
    this.expiryDate,
    this.term,
  });

  factory PassHolder.fromJson(Map<String, dynamic> json) => PassHolder(
    name: '${json['name'] ?? ''}',
    membershipName: '${json['membershipName'] ?? ''}',
    startDate: _date(json['startDate']),
    expiryDate: _date(json['expiryDate']),
    term: PassTerm.tryParse(json['term']),
  );

  final String name;
  final String membershipName;
  final DateTime? startDate;
  final DateTime? expiryDate;
  final PassTerm? term;

  @override
  List<Object?> get props => [
    name,
    membershipName,
    startDate,
    expiryDate,
    term,
  ];
}

/// One signed pass code for one 30-second slot. Kept in memory only.
class PassCode extends Equatable {
  const PassCode({required this.slot, required this.code});

  final int slot;
  final String code;

  static PassCode? tryParse(Map<dynamic, dynamic> json) {
    final slot = _int(json['slot']);
    final code = _text(json['code']);
    if (slot == null || code == null) return null;
    return PassCode(slot: slot, code: code);
  }

  @override
  List<Object?> get props => [slot, code];

  @override
  bool? get stringify => false;

  @override
  String toString() => 'PassCode(slot: $slot)';
}

/// Today's shared color, compared at a glance by door staff.
class DayColor extends Equatable {
  const DayColor({required this.name, required this.hex});

  factory DayColor.fromJson(Object? json) {
    final map = _map(json);
    return DayColor(name: '${map['name'] ?? ''}', hex: '${map['hex'] ?? ''}');
  }

  static const names = [
    'red',
    'orange',
    'yellow',
    'lime',
    'green',
    'teal',
    'cyan',
    'blue',
    'indigo',
    'purple',
    'pink',
    'brown',
  ];

  final String name;
  final String hex;

  Color get color {
    final digits = hex.startsWith('#') ? hex.substring(1) : hex;
    final value = digits.length == 6 ? int.tryParse(digits, radix: 16) : null;
    return Color(0xFF000000 | (value ?? 0x8E8E93));
  }

  @override
  List<Object?> get props => [name, hex];
}

class WalletAvailability extends Equatable {
  const WalletAvailability({required this.apple, required this.google});

  factory WalletAvailability.fromJson(Object? json) {
    final map = _map(json);
    return WalletAvailability(
      apple: map['apple'] == true,
      google: map['google'] == true,
    );
  }

  final bool apple;
  final bool google;

  @override
  List<Object?> get props => [apple, google];
}

/// What `GET /api/member-pass` answered.
sealed class MemberPassResponse extends Equatable {
  const MemberPassResponse();

  factory MemberPassResponse.fromJson(Map<String, dynamic> json) {
    if (json['state'] != 'active') {
      return NoPass(NoPassState.fromValue(json['state']?.toString()));
    }
    final rawCodes = json['codes'];
    final codes =
        (rawCodes is List ? rawCodes : const [])
            .whereType<Map>()
            .map(PassCode.tryParse)
            .whereType<PassCode>()
            .toList()
          ..sort((a, b) => a.slot.compareTo(b.slot));
    final serverNow = _int(json['serverNow']);
    final holder = json['holder'];
    if (codes.isEmpty || serverNow == null || holder is! Map) {
      return const NoPass(NoPassState.unavailable);
    }
    return ActivePass(
      holder: PassHolder.fromJson(Map<String, dynamic>.from(holder)),
      codes: List.unmodifiable(codes),
      dayColor: DayColor.fromJson(json['dayColor']),
      serverNow: serverNow,
      wallets: WalletAvailability.fromJson(json['wallets']),
    );
  }

  @override
  bool? get stringify => false;
}

class ActivePass extends MemberPassResponse {
  const ActivePass({
    required this.holder,
    required this.codes,
    required this.dayColor,
    required this.serverNow,
    required this.wallets,
  });

  final PassHolder holder;
  final List<PassCode> codes;
  final DayColor dayColor;

  /// Server clock in Unix milliseconds when the body was made.
  final int serverNow;
  final WalletAvailability wallets;

  @override
  List<Object?> get props => [holder, codes, dayColor, serverNow, wallets];

  @override
  String toString() => 'ActivePass(${codes.length} codes)';
}

class NoPass extends MemberPassResponse {
  const NoPass(this.state);

  final NoPassState state;

  @override
  List<Object?> get props => [state];

  @override
  String toString() => 'NoPass(${state.value})';
}

/// The signed-in user's scanner grant.
class ScannerAccess extends Equatable {
  const ScannerAccess({this.campusId, this.expiresAt, required this.dayColor});

  factory ScannerAccess.fromJson(Map<String, dynamic> json) => ScannerAccess(
    campusId: _text(json['campusId']),
    expiresAt: _date(json['expiresAt']),
    dayColor: DayColor.fromJson(json['dayColor']),
  );

  final String? campusId;
  final DateTime? expiresAt;
  final DayColor dayColor;

  @override
  List<Object?> get props => [campusId, expiresAt, dayColor];
}

enum ScanResult { valid, duplicate, checkId, denied, unavailable }

enum DenyReason { badCode, stale, expired, notMember, notLinked, other }

/// What `POST /api/member-pass/scan` answered.
class ScanOutcome extends Equatable {
  const ScanOutcome({
    required this.result,
    this.reason,
    this.name,
    this.membershipName,
    this.expiryDate,
    this.secondsSincePrevious,
  });

  factory ScanOutcome.fromJson(Map<String, dynamic> json) {
    final result = switch (json['result']) {
      'valid' => ScanResult.valid,
      'duplicate' => ScanResult.duplicate,
      'check_id' => ScanResult.checkId,
      'denied' => ScanResult.denied,
      _ => ScanResult.unavailable,
    };
    final reason = result != ScanResult.denied
        ? null
        : switch (json['reason']) {
            'bad_code' => DenyReason.badCode,
            'stale' => DenyReason.stale,
            'expired' => DenyReason.expired,
            'not_member' => DenyReason.notMember,
            'not_linked' => DenyReason.notLinked,
            _ => DenyReason.other,
          };
    return ScanOutcome(
      result: result,
      reason: reason,
      name: _text(json['name']),
      membershipName: _text(json['membershipName']),
      expiryDate: _date(json['expiryDate']),
      secondsSincePrevious: _int(json['secondsSincePrevious']),
    );
  }

  final ScanResult result;
  final DenyReason? reason;
  final String? name;
  final String? membershipName;
  final DateTime? expiryDate;
  final int? secondsSincePrevious;

  @override
  List<Object?> get props => [
    result,
    reason,
    name,
    membershipName,
    expiryDate,
    secondsSincePrevious,
  ];
}
