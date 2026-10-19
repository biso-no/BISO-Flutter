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

/// Whether an offered plan starts this season or the next one.
enum MembershipPlanOffer {
  current('current'),
  next('next');

  const MembershipPlanOffer(this.value);

  final String value;

  /// A server that predates next-season offers sends no `offer`; everything
  /// it sells starts this season.
  static MembershipPlanOffer fromValue(String? value) =>
      value == next.value ? next : current;
}

/// A membership plan the student may buy right now.
class MembershipPlanOption extends Equatable {
  final String id;

  /// The 24SevenOffice product name ("BISO Membership fall 2026"). Not for
  /// display: rows are labelled by [duration].
  final String name;
  final double price;
  final String duration;
  final int accrualMonths;
  final MembershipPlanOffer offer;
  final DateTime? startDate;
  final DateTime? expiryDate;

  const MembershipPlanOption({
    required this.id,
    required this.name,
    required this.price,
    required this.duration,
    required this.accrualMonths,
    this.offer = MembershipPlanOffer.current,
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
      offer: MembershipPlanOffer.fromValue(json['offer']?.toString()),
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
    'offer': offer.value,
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
    offer,
    startDate,
    expiryDate,
  ];
}

/// The plans of one duration on offer: the one starting this season, the one
/// starting next season, or both (in June and December, and for renewals).
class MembershipPlanChoice extends Equatable {
  final String duration;
  final MembershipPlanOption? current;
  final MembershipPlanOption? next;

  const MembershipPlanChoice({required this.duration, this.current, this.next})
    : assert(current != null || next != null);

  /// The plan the row shows until the student picks otherwise.
  MembershipPlanOption get primary => current ?? next!;

  /// Both starts are on offer, so the student chooses between them.
  bool get hasChoice => current != null && next != null;

  /// The plan that is bought: next season's when the student chose it and it
  /// is on offer, otherwise [primary].
  MembershipPlanOption plan({required bool startNext}) =>
      startNext ? next ?? primary : primary;

  @override
  List<Object?> get props => [duration, current, next];
}

const _durationOrder = ['semester', 'year', 'three_years'];

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

  /// Bought but not started yet, earliest start first. These give no
  /// benefits until they start.
  final List<MembershipPeriod> upcomingMemberships;
  final List<MembershipPeriod> expiredMemberships;

  /// The latest expiry across active and upcoming memberships.
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
    this.upcomingMemberships = const [],
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
      upcomingMemberships: _parseList(
        json['upcomingMemberships'],
        MembershipPeriod.fromJson,
      ),
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
    'upcomingMemberships': upcomingMemberships.map((m) => m.toJson()).toList(),
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
    upcomingMemberships: upcomingMemberships,
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

  /// The membership a student who is not a member yet has bought, starting
  /// later. Null for a member: their upcoming plans only extend what they
  /// already hold.
  MembershipPeriod? get upcomingMembership =>
      isMember || upcomingMemberships.isEmpty
      ? null
      : upcomingMemberships.first;

  /// The offered plans, one choice per duration, semester first. A duration
  /// this app does not know goes last, in the order the server sent it.
  List<MembershipPlanChoice> get planChoices {
    final current = <String, MembershipPlanOption>{};
    final next = <String, MembershipPlanOption>{};
    final durations = <String>[];
    for (final plan in offeredPlans) {
      if (!durations.contains(plan.duration)) durations.add(plan.duration);
      final slot = plan.offer == MembershipPlanOffer.next ? next : current;
      slot.putIfAbsent(plan.duration, () => plan);
    }
    int rank(String duration) {
      final index = _durationOrder.indexOf(duration);
      return index < 0 ? _durationOrder.length : index;
    }

    final ordered = [...durations]
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0
            ? byRank
            : durations.indexOf(a).compareTo(durations.indexOf(b));
      });
    return [
      for (final duration in ordered)
        MembershipPlanChoice(
          duration: duration,
          current: current[duration],
          next: next[duration],
        ),
    ];
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
    upcomingMemberships,
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
