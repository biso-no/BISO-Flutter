import 'package:biso/data/models/membership_overview.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> serverOverview({
  String state = 'eligible',
  bool isMember = true,
}) => {
  'state': state,
  'studentId': 's1715738',
  'isMember': isMember,
  'memberships': [
    {
      'id': 'semester',
      'name': 'BISO Membership fall 2026',
      'category': '113176',
      'startDate': '2026-08-01',
      'expiryDate': '2026-12-31',
    },
    {
      'id': 'year',
      'name': 'BISO Membership fall 2026 and spring 2027',
      'category': '113178',
      'startDate': '2026-08-01',
      'expiryDate': '2027-06-30',
    },
  ],
  'expiredMemberships': [
    {
      'id': 'spring',
      'name': 'BISO Membership spring 2026',
      'category': '113170',
      'startDate': '2026-01-01',
      'expiryDate': '2026-06-30',
    },
  ],
  'currentExpiry': '2027-06-30',
  'reason': null,
  'checkedAt': '2026-09-15T08:00:00.000Z',
  'offeredPlans': [
    {
      'id': '82',
      'name': 'BISO Membership fall 2026 - spring 2029',
      'price': 1350,
      'duration': 'three_years',
      'accrualMonths': 36,
      'startDate': '2026-08-01',
      'expiryDate': '2029-06-30',
    },
  ],
  'defaultCampusId': '2',
  'campuses': [
    {'id': '1', 'name': 'Oslo'},
    {'id': '2', 'name': 'Bergen'},
  ],
};

void main() {
  test('reads the server overview', () {
    final overview = MembershipOverview.fromJson(serverOverview());

    expect(overview.state, MembershipGateState.eligible);
    expect(overview.studentId, 's1715738');
    expect(overview.isMember, isTrue);
    expect(overview.currentMembership?.id, 'year');
    expect(overview.lastExpiredMembership?.id, 'spring');
    expect(overview.currentExpiry, DateTime(2027, 6, 30));
    expect(overview.checkedAt, DateTime.utc(2026, 9, 15, 8));
    expect(overview.offeredPlans.single.price, 1350);
    expect(overview.offeredPlans.single.accrualMonths, 36);
    expect(overview.campuses.map((c) => c.name), ['Oslo', 'Bergen']);
    expect(overview.canPurchase, isTrue);
    expect(overview.isLinked, isTrue);
    expect(overview.fromCache, isFalse);
  });

  test('never reads an unknown state as permission to buy', () {
    final overview = MembershipOverview.fromJson(
      serverOverview(state: 'something_new'),
    );

    expect(overview.state, MembershipGateState.checkUnavailable);
    expect(overview.canPurchase, isFalse);
  });

  test('an unlinked student is not linked and cannot buy', () {
    final overview = MembershipOverview.fromJson({
      ...serverOverview(state: 'needs_bi_link', isMember: false),
      'studentId': null,
      'memberships': <Object>[],
      'offeredPlans': <Object>[],
    });

    expect(overview.isLinked, isFalse);
    expect(overview.canPurchase, isFalse);
    expect(overview.currentMembership, isNull);
  });

  test('survives a round trip through the device cache, marked as cached', () {
    final original = MembershipOverview.fromJson(serverOverview());

    final restored = MembershipOverview.fromJson(original.toJson()).asCached();

    expect(restored.fromCache, isTrue);
    expect(restored.state, original.state);
    expect(restored.memberships, original.memberships);
    expect(restored.expiredMemberships, original.expiredMemberships);
    expect(restored.offeredPlans, original.offeredPlans);
    expect(restored.checkedAt, original.checkedAt);
  });
}
