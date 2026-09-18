import 'package:equatable/equatable.dart';

DateTime? _parseDate(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());

String? _formatDate(DateTime? value) => value?.toIso8601String();

List<T> _parseList<T>(Object? value, T Function(Map<String, dynamic>) parse) {
  if (value is! List) return <T>[];
  return value
      .whereType<Map>()
      .map((entry) => parse(Map<String, dynamic>.from(entry)))
      .toList(growable: false);
}

/// Where a student stands on buying a membership. The server decides it with
/// the same gate biso.no's join page uses.
enum MembershipGateState {
  needsBiLink('needs_bi_link'),
  needsDirectoryRecord('needs_directory_record'),
  checkUnavailable('membership_check_unavailable'),
  alreadyMember('already_member'),
  noPlansAvailable('no_plans_available'),
  eligible('eligible');

  const MembershipGateState(this.value);

  final String value;

  /// An unknown state reads as "cannot tell right now", never as eligible.
  static MembershipGateState fromValue(String? value) {
    for (final state in MembershipGateState.values) {
      if (state.value == value) return state;
    }
    return MembershipGateState.checkUnavailable;
  }
}

/// One membership period a student holds, or held.
class MembershipPeriod extends Equatable {
  final String id;
  final String name;
  final String? category;
  final DateTime? startDate;
  final DateTime? expiryDate;

  const MembershipPeriod({
    required this.id,
    required this.name,
    this.category,
    this.startDate,
    this.expiryDate,
  });

  factory MembershipPeriod.fromJson(Map<String, dynamic> json) {
    return MembershipPeriod(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      category: json['category']?.toString(),
      startDate: _parseDate(json['startDate']),
      expiryDate: _parseDate(json['expiryDate']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'startDate': _formatDate(startDate),
    'expiryDate': _formatDate(expiryDate),
  };

  @override
  List<Object?> get props => [id, name, category, startDate, expiryDate];
}

/// A membership plan the student may buy right now.
class MembershipPlanOption extends Equatable {
  final String id;
  final String name;
  final double price;
  final String duration;
  final int accrualMonths;
  final DateTime? startDate;
  final DateTime? expiryDate;

  const MembershipPlanOption({
    required this.id,
    required this.name,
    required this.price,
    required this.duration,
    required this.accrualMonths,
    this.startDate,
    this.expiryDate,
  });

  factory MembershipPlanOption.fromJson(Map<String, dynamic> json) {
    return MembershipPlanOption(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      price: (json['price'] as num?)?.toDouble() ?? 0,
      duration: (json['duration'] ?? '').toString(),
      accrualMonths: (json['accrualMonths'] as num?)?.toInt() ?? 0,
      startDate: _parseDate(json['startDate']),
      expiryDate: _parseDate(json['expiryDate']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'duration': duration,
    'accrualMonths': accrualMonths,
    'startDate': _formatDate(startDate),
    'expiryDate': _formatDate(expiryDate),
  };

  @override
  List<Object?> get props => [
    id,
    name,
    price,
    duration,
    accrualMonths,
    startDate,
    expiryDate,
  ];
}

/// A BI campus a membership can be booked to.
class MembershipCampus extends Equatable {
  final String id;
  final String name;

  const MembershipCampus({required this.id, required this.name});

  factory MembershipCampus.fromJson(Map<String, dynamic> json) =>
      MembershipCampus(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  @override
  List<Object?> get props => [id, name];
}

/// The signed-in student's membership, as `GET /api/membership` reports it:
/// live 24SevenOffice status with expired memberships excluded, the purchase
/// gate, and the plans on offer.
class MembershipOverview extends Equatable {
  final MembershipGateState state;
  final String? studentId;
  final bool isMember;
  final List<MembershipPeriod> memberships;
  final List<MembershipPeriod> expiredMemberships;
  final DateTime? currentExpiry;
  final String? reason;
  final DateTime checkedAt;
  final List<MembershipPlanOption> offeredPlans;
  final String? defaultCampusId;
  final List<MembershipCampus> campuses;

  /// The last verified overview kept on this device, shown because a fresh
  /// check could not be made.
  final bool fromCache;

  const MembershipOverview({
    required this.state,
    required this.isMember,
    required this.checkedAt,
    this.studentId,
    this.memberships = const [],
    this.expiredMemberships = const [],
    this.currentExpiry,
    this.reason,
    this.offeredPlans = const [],
    this.defaultCampusId,
    this.campuses = const [],
    this.fromCache = false,
  });

  factory MembershipOverview.fromJson(
    Map<String, dynamic> json, {
    bool fromCache = false,
  }) {
    return MembershipOverview(
      state: MembershipGateState.fromValue(json['state']?.toString()),
      studentId: json['studentId']?.toString(),
      isMember: json['isMember'] == true,
      memberships: _parseList(json['memberships'], MembershipPeriod.fromJson),
      expiredMemberships: _parseList(
        json['expiredMemberships'],
        MembershipPeriod.fromJson,
      ),
      currentExpiry: _parseDate(json['currentExpiry']),
      reason: json['reason']?.toString(),
      checkedAt: _parseDate(json['checkedAt']) ?? DateTime.now(),
      offeredPlans: _parseList(
        json['offeredPlans'],
        MembershipPlanOption.fromJson,
      ),
      defaultCampusId: json['defaultCampusId']?.toString(),
      campuses: _parseList(json['campuses'], MembershipCampus.fromJson),
      fromCache: fromCache,
    );
  }

  Map<String, dynamic> toJson() => {
    'state': state.value,
    'studentId': studentId,
    'isMember': isMember,
    'memberships': memberships.map((m) => m.toJson()).toList(),
    'expiredMemberships': expiredMemberships.map((m) => m.toJson()).toList(),
    'currentExpiry': _formatDate(currentExpiry),
    'reason': reason,
    'checkedAt': checkedAt.toIso8601String(),
    'offeredPlans': offeredPlans.map((p) => p.toJson()).toList(),
    'defaultCampusId': defaultCampusId,
    'campuses': campuses.map((c) => c.toJson()).toList(),
  };

  MembershipOverview asCached() => MembershipOverview(
    state: state,
    studentId: studentId,
    isMember: isMember,
    memberships: memberships,
    expiredMemberships: expiredMemberships,
    currentExpiry: currentExpiry,
    reason: reason,
    checkedAt: checkedAt,
    offeredPlans: offeredPlans,
    defaultCampusId: defaultCampusId,
    campuses: campuses,
    fromCache: true,
  );

  /// A BI student account is linked (or the link could not be checked).
  bool get isLinked => state != MembershipGateState.needsBiLink;

  bool get canPurchase =>
      state == MembershipGateState.eligible && offeredPlans.isNotEmpty;

  /// The active membership that runs longest.
  MembershipPeriod? get currentMembership {
    if (memberships.isEmpty) return null;
    final sorted = [...memberships]
      ..sort((a, b) {
        final left = a.expiryDate ?? DateTime(0);
        final right = b.expiryDate ?? DateTime(0);
        return right.compareTo(left);
      });
    return sorted.first;
  }

  /// The most recently expired membership (the server sends newest first).
  MembershipPeriod? get lastExpiredMembership =>
      expiredMemberships.isEmpty ? null : expiredMemberships.first;

  @override
  List<Object?> get props => [
    state,
    studentId,
    isMember,
    memberships,
    expiredMemberships,
    currentExpiry,
    reason,
    checkedAt,
    offeredPlans,
    defaultCampusId,
    campuses,
    fromCache,
  ];
}
