import 'package:biso/data/models/membership_overview.dart';

/// Plans as `GET /api/membership` offers them after BISO-Sites PR #83. The
/// names are 24SevenOffice product names and must never reach the screen.
MembershipPlanOption membershipPlan(
  String id, {
  required String duration,
  required DateTime start,
  required DateTime end,
  required double price,
  MembershipPlanOffer offer = MembershipPlanOffer.current,
}) => MembershipPlanOption(
  id: id,
  name: 'BISO Membership product $id',
  price: price,
  duration: duration,
  accrualMonths: switch (duration) {
    'semester' => 6,
    'year' => 12,
    _ => 36,
  },
  offer: offer,
  startDate: start,
  expiryDate: end,
);

final fall2026Semester = membershipPlan(
  '54',
  duration: 'semester',
  start: DateTime(2026, 7, 1),
  end: DateTime(2026, 12, 31),
  price: 350,
);

final fall2026Year = membershipPlan(
  '55',
  duration: 'year',
  start: DateTime(2026, 7, 1),
  end: DateTime(2027, 6, 30),
  price: 550,
);

final fall2026ThreeYears = membershipPlan(
  '56',
  duration: 'three_years',
  start: DateTime(2026, 7, 1),
  end: DateTime(2029, 6, 30),
  price: 1350,
);

final spring2027Semester = membershipPlan(
  '60',
  duration: 'semester',
  start: DateTime(2027, 1, 1),
  end: DateTime(2027, 6, 30),
  price: 350,
  offer: MembershipPlanOffer.next,
);

final spring2027Year = membershipPlan(
  '61',
  duration: 'year',
  start: DateTime(2027, 1, 1),
  end: DateTime(2027, 12, 31),
  price: 550,
  offer: MembershipPlanOffer.next,
);

final spring2027ThreeYears = membershipPlan(
  '62',
  duration: 'three_years',
  start: DateTime(2027, 1, 1),
  end: DateTime(2029, 12, 31),
  price: 1350,
  offer: MembershipPlanOffer.next,
);

MembershipPeriod membershipPeriodOf(MembershipPlanOption plan) =>
    MembershipPeriod(
      id: plan.id,
      name: plan.name,
      category: 'category-${plan.id}',
      startDate: plan.startDate,
      expiryDate: plan.expiryDate,
    );

MembershipOverview membershipOverviewOf({
  MembershipGateState state = MembershipGateState.eligible,
  bool isMember = false,
  List<MembershipPlanOption> plans = const [],
  List<MembershipPlanOption> active = const [],
  List<MembershipPlanOption> upcoming = const [],
  DateTime? currentExpiry,
}) => MembershipOverview(
  state: state,
  isMember: isMember,
  studentId: 's1715738',
  checkedAt: DateTime.now(),
  memberships: [for (final plan in active) membershipPeriodOf(plan)],
  upcomingMemberships: [for (final plan in upcoming) membershipPeriodOf(plan)],
  currentExpiry: currentExpiry,
  reason: !isMember && upcoming.isNotEmpty ? 'upcoming' : null,
  offeredPlans: plans,
  defaultCampusId: '2',
  campuses: const [
    MembershipCampus(id: '1', name: 'Oslo'),
    MembershipCampus(id: '2', name: 'Bergen'),
  ],
);
