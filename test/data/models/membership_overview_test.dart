import 'package:biso/data/models/membership_overview.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/membership_fixtures.dart';

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

  group('after BISO-Sites PR #83', () {
    Map<String, dynamic> plan(
      String id,
      String duration, {
      String? offer,
      required String start,
      required String end,
    }) => {
      'id': id,
      'name': 'BISO Membership $id',
      'duration': duration,
      'offer': ?offer,
      'price': 350,
      'accrualMonths': 6,
      'startDate': start,
      'expiryDate': end,
    };

    test('reads offer and upcoming memberships', () {
      final overview = MembershipOverview.fromJson({
        ...serverOverview(state: 'already_member', isMember: false),
        'memberships': <Object>[],
        'upcomingMemberships': [
          {
            'id': '60',
            'name': 'BISO Membership spring 2027',
            'category': '113180',
            'startDate': '2027-01-01',
            'expiryDate': '2027-06-30',
          },
        ],
        'reason': 'upcoming',
        'offeredPlans': [
          plan('54', 'semester', start: '2026-07-01', end: '2026-12-31'),
          plan(
            '60',
            'semester',
            offer: 'next',
            start: '2027-01-01',
            end: '2027-06-30',
          ),
        ],
      });

      expect(overview.reason, 'upcoming');
      expect(overview.upcomingMemberships.single.id, '60');
      expect(overview.upcomingMembership?.startDate, DateTime(2027, 1, 1));
      expect(overview.offeredPlans.map((p) => p.offer), [
        MembershipPlanOffer.current,
        MembershipPlanOffer.next,
      ]);
    });

    test('an old server without the new fields reads as before', () {
      final overview = MembershipOverview.fromJson(serverOverview());

      expect(overview.upcomingMemberships, isEmpty);
      expect(overview.upcomingMembership, isNull);
      expect(overview.offeredPlans.single.offer, MembershipPlanOffer.current);
      final choice = overview.planChoices.single;
      expect(choice.duration, 'three_years');
      expect(choice.hasChoice, isFalse);
      expect(choice.plan(startNext: true).id, '82');
    });

    test('an unknown offer reads as current', () {
      final option = MembershipPlanOption.fromJson(
        plan(
          '1',
          'year',
          offer: 'someday',
          start: '2026-07-01',
          end: '2027-06-30',
        ),
      );
      expect(option.offer, MembershipPlanOffer.current);
    });

    test('a member has no upcoming membership to announce', () {
      final overview = membershipOverviewOf(
        state: MembershipGateState.eligible,
        isMember: true,
        active: [fall2026Semester],
        upcoming: [spring2027Semester],
      );
      expect(overview.upcomingMembership, isNull);
    });

    test('groups offers by duration, semester first, one row each', () {
      final overview = membershipOverviewOf(
        plans: [
          fall2026ThreeYears,
          spring2027Semester,
          fall2026Year,
          fall2026Semester,
          spring2027ThreeYears,
          spring2027Year,
        ],
      );

      final choices = overview.planChoices;
      expect(choices.map((c) => c.duration), [
        'semester',
        'year',
        'three_years',
      ]);
      expect(choices.every((c) => c.hasChoice), isTrue);
      final semester = choices.first;
      expect(semester.primary, fall2026Semester);
      expect(semester.plan(startNext: false), fall2026Semester);
      expect(semester.plan(startNext: true), spring2027Semester);
    });

    test('a duration offered only for next season shows that plan', () {
      final overview = membershipOverviewOf(
        isMember: true,
        plans: [spring2027Semester, fall2026Year, fall2026ThreeYears],
      );

      final semester = overview.planChoices.first;
      expect(semester.hasChoice, isFalse);
      expect(semester.primary, spring2027Semester);
      expect(semester.plan(startNext: false), spring2027Semester);
    });

    test('the cache round trip keeps upcoming memberships and offers', () {
      final original = membershipOverviewOf(
        state: MembershipGateState.eligible,
        plans: [fall2026Year, spring2027Year],
        upcoming: [spring2027Semester],
        currentExpiry: DateTime(2027, 6, 30),
      );

      final restored = MembershipOverview.fromJson(
        original.toJson(),
      ).asCached();

      expect(restored.upcomingMemberships, original.upcomingMemberships);
      expect(restored.offeredPlans, original.offeredPlans);
      expect(restored.planChoices, original.planChoices);
      expect(restored.upcomingMembership, original.upcomingMembership);
    });
  });
}
