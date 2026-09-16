import 'dart:convert';

import 'package:biso/data/models/membership_overview.dart';
import 'package:biso/data/models/payment_provider.dart';
import 'package:biso/data/services/membership_api_client.dart';
import 'package:biso/data/services/shop_api_client.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

MembershipOverview overview({
  MembershipGateState state = MembershipGateState.eligible,
  bool isMember = true,
  DateTime? checkedAt,
}) => MembershipOverview(
  state: state,
  isMember: isMember,
  studentId: 's1715738',
  checkedAt: checkedAt ?? DateTime.now(),
  memberships: isMember
      ? [
          MembershipPeriod(
            id: 'year',
            name: 'BISO Membership fall 2026 and spring 2027',
            expiryDate: DateTime(2027, 6, 30),
          ),
        ]
      : const [],
);

class _FakeMembershipApi extends MembershipApiClient {
  _FakeMembershipApi(this._answer);

  Future<MembershipOverview> Function() _answer;
  final List<bool> refreshes = [];

  set answer(Future<MembershipOverview> Function() value) => _answer = value;

  @override
  Future<MembershipOverview> fetchOverview({bool refresh = false}) {
    refreshes.add(refresh);
    return _answer();
  }

  @override
  Future<StartedCheckout> startCheckout({
    required PaymentProvider provider,
    required String planId,
    required String campusId,
  }) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer container(_FakeMembershipApi api, {String? userId = 'user-1'}) {
    final c = ProviderContainer(
      overrides: [
        membershipApiClientProvider.overrideWithValue(api),
        membershipUserIdProvider.overrideWithValue(userId),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('there is nothing to verify for a signed-out visitor', () async {
    final api = _FakeMembershipApi(() async => overview());
    final c = container(api, userId: null);

    expect(await c.read(membershipOverviewProvider.future), isNull);
    expect(api.refreshes, isEmpty);
  });

  test('verifies at launch and keeps the result for this student', () async {
    final api = _FakeMembershipApi(() async => overview());
    final c = container(api);

    final result = await c.read(membershipOverviewProvider.future);

    expect(result?.isMember, isTrue);
    expect(result?.fromCache, isFalse);
    expect(api.refreshes, [false]);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(MembershipOverviewNotifier.cacheKey('user-1')),
      isNotNull,
    );
  });

  test('shows the last verified result, marked cached, when the check fails', () async {
    final saved = overview(checkedAt: DateTime.now().subtract(const Duration(hours: 3)));
    SharedPreferences.setMockInitialValues(<String, Object>{
      MembershipOverviewNotifier.cacheKey('user-1'): jsonEncode(saved.toJson()),
    });
    final api = _FakeMembershipApi(() async => throw Exception('offline'));
    final c = container(api);

    final result = await c.read(membershipOverviewProvider.future);

    expect(result?.fromCache, isTrue);
    expect(result?.isMember, isTrue);
  });

  test("prefers the cached result over the server's 'cannot verify right now'", () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      MembershipOverviewNotifier.cacheKey('user-1'): jsonEncode(
        overview().toJson(),
      ),
    });
    final api = _FakeMembershipApi(
      () async => overview(
        state: MembershipGateState.checkUnavailable,
        isMember: false,
      ),
    );
    final c = container(api);

    final result = await c.read(membershipOverviewProvider.future);

    expect(result?.fromCache, isTrue);
    expect(result?.isMember, isTrue);
  });

  test("shows 'cannot verify right now' when nothing is cached", () async {
    final api = _FakeMembershipApi(
      () async => overview(
        state: MembershipGateState.checkUnavailable,
        isMember: false,
      ),
    );
    final c = container(api);

    final result = await c.read(membershipOverviewProvider.future);

    expect(result?.state, MembershipGateState.checkUnavailable);
    expect(result?.fromCache, isFalse);
  });

  test('a refresh asks the server to re-check', () async {
    final api = _FakeMembershipApi(() async => overview(isMember: false));
    final c = container(api);
    await c.read(membershipOverviewProvider.future);
    api.answer = () async => overview();

    await c.read(membershipOverviewProvider.notifier).refresh();

    expect(api.refreshes, [false, true]);
    expect(c.read(membershipOverviewProvider).valueOrNull?.isMember, isTrue);
  });

  test('member-only products trust a cached membership for a day only', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      MembershipOverviewNotifier.cacheKey('user-1'): jsonEncode(
        overview(checkedAt: DateTime.now().subtract(const Duration(hours: 30)))
            .toJson(),
      ),
    });
    final api = _FakeMembershipApi(() async => throw Exception('offline'));
    final c = container(api);

    await c.read(membershipOverviewProvider.future);

    expect(c.read(hasValidMembershipProvider), isFalse);
  });

  test('a freshly verified membership counts', () async {
    final api = _FakeMembershipApi(() async => overview());
    final c = container(api);

    await c.read(membershipOverviewProvider.future);

    expect(c.read(hasValidMembershipProvider), isTrue);
  });
}
