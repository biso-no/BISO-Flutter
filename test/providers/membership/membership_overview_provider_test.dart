import 'dart:async';
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

  ProviderContainer container(
    _FakeMembershipApi api, {
    String? userId = 'user-1',
  }) {
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

  test(
    'shows the last verified result, marked cached, when the check fails',
    () async {
      final saved = overview(
        checkedAt: DateTime.now().subtract(const Duration(hours: 3)),
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        MembershipOverviewNotifier.cacheKey('user-1'): jsonEncode(
          saved.toJson(),
        ),
      });
      final api = _FakeMembershipApi(() async => throw Exception('offline'));
      final c = container(api);

      final result = await c.read(membershipOverviewProvider.future);

      expect(result?.fromCache, isTrue);
      expect(result?.isMember, isTrue);
    },
  );

  test(
    "prefers the cached result over the server's 'cannot verify right now'",
    () async {
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
    },
  );

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

  test(
    'member-only products trust a cached membership for a day only',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        MembershipOverviewNotifier.cacheKey('user-1'): jsonEncode(
          overview(
            checkedAt: DateTime.now().subtract(const Duration(hours: 30)),
          ).toJson(),
        ),
      });
      final api = _FakeMembershipApi(() async => throw Exception('offline'));
      final c = container(api);

      await c.read(membershipOverviewProvider.future);

      expect(c.read(hasValidMembershipProvider), isFalse);
    },
  );

  test('a freshly verified membership counts', () async {
    final api = _FakeMembershipApi(() async => overview());
    final c = container(api);

    await c.read(membershipOverviewProvider.future);

    expect(c.read(hasValidMembershipProvider), isTrue);
  });

  // Fix round 1: `onAppResumed` (formerly a private `_onResume` reachable
  // only through a real AppLifecycleListener event) is now public and
  // directly testable.

  test('onAppResumed refetches when the overview is older than the recheck '
      'window', () async {
    final api = _FakeMembershipApi(
      () async => overview(
        checkedAt: DateTime.now().subtract(const Duration(minutes: 11)),
      ),
    );
    final c = container(api);
    await c.read(membershipOverviewProvider.future);
    expect(api.refreshes, [false]);

    api.answer = () async => overview();
    await c.read(membershipOverviewProvider.notifier).onAppResumed();

    expect(api.refreshes, [false, false]);
  });

  test('onAppResumed does nothing when the overview is still fresh', () async {
    final api = _FakeMembershipApi(() async => overview());
    final c = container(api);
    await c.read(membershipOverviewProvider.future);
    expect(api.refreshes, [false]);

    await c.read(membershipOverviewProvider.notifier).onAppResumed();

    expect(api.refreshes, [false]);
  });

  test('after noteLinkStarted, the next onAppResumed refetches even when the '
      'overview is fresh', () async {
    final api = _FakeMembershipApi(() async => overview());
    final c = container(api);
    await c.read(membershipOverviewProvider.future);
    expect(api.refreshes, [false]);

    final notifier = c.read(membershipOverviewProvider.notifier);
    notifier.noteLinkStarted();
    await notifier.onAppResumed();

    expect(api.refreshes, [false, true]);
  });

  test(
    'onAppResumed refetches a fromCache overview regardless of age',
    () async {
      final saved = overview(checkedAt: DateTime.now());
      SharedPreferences.setMockInitialValues(<String, Object>{
        MembershipOverviewNotifier.cacheKey('user-1'): jsonEncode(
          saved.toJson(),
        ),
      });
      final api = _FakeMembershipApi(() async => throw Exception('offline'));
      final c = container(api);
      final result = await c.read(membershipOverviewProvider.future);
      expect(result?.fromCache, isTrue);
      expect(api.refreshes, [false]);

      api.answer = () async => overview();
      await c.read(membershipOverviewProvider.notifier).onAppResumed();

      expect(api.refreshes, [false, false]);
    },
  );

  test(
    'a plain failure with nothing cached surfaces as an error state',
    () async {
      final api = _FakeMembershipApi(() async => throw Exception('offline'));
      final c = container(api);

      await expectLater(
        c.read(membershipOverviewProvider.future),
        throwsException,
      );
      expect(c.read(membershipOverviewProvider).hasError, isTrue);
    },
  );

  // Fix round 1, finding 1: a fetch started for one account must not
  // overwrite the state, or that account's cache entry, once a different
  // (or no) account is current by the time it resolves. The initial load
  // and the stale in-flight one return different `isMember` values
  // specifically so a wrongly-applied state or cache write is distinguishable
  // from a correctly-dropped one.
  test(
    'a refresh in flight for one account is dropped, and does not touch its '
    'cache entry, once the account has moved on before it resolves',
    () async {
      String? currentId = 'user-1';
      final completer = Completer<MembershipOverview>();
      final api = _FakeMembershipApi(() async => overview(isMember: false));
      final c = ProviderContainer(
        overrides: [
          membershipApiClientProvider.overrideWithValue(api),
          membershipUserIdProvider.overrideWith((ref) => currentId),
        ],
      );
      addTearDown(c.dispose);

      await c.read(membershipOverviewProvider.future);

      api.answer = () => completer.future;
      final staleRefresh = c
          .read(membershipOverviewProvider.notifier)
          .refresh();

      // The account signs out (or switches) while that refresh is still in
      // flight.
      currentId = null;
      c.invalidate(membershipUserIdProvider);
      expect(await c.read(membershipOverviewProvider.future), isNull);

      // The stale fetch — for an account that is no longer current — now
      // resolves, with a result that would be wrong to show or to cache.
      completer.complete(overview(isMember: true));
      await staleRefresh;

      expect(c.read(membershipOverviewProvider).valueOrNull, isNull);
      final prefs = await SharedPreferences.getInstance();
      final cached =
          jsonDecode(
                prefs.getString(MembershipOverviewNotifier.cacheKey('user-1'))!,
              )
              as Map<String, dynamic>;
      // Still the initial, legitimate load (isMember: false) — the stale
      // fetch's isMember: true was never written.
      expect(cached['isMember'], isFalse);
    },
  );

  // Fix round 1, finding 2: switching accounts must not mix up per-account
  // cache entries.
  test('two different accounts in one container run keep separate cache '
      'entries', () async {
    String? currentId = 'user-1';
    final api = _FakeMembershipApi(() async => overview(isMember: true));
    final c = ProviderContainer(
      overrides: [
        membershipApiClientProvider.overrideWithValue(api),
        membershipUserIdProvider.overrideWith((ref) => currentId),
      ],
    );
    addTearDown(c.dispose);

    await c.read(membershipOverviewProvider.future);

    api.answer = () async => overview(isMember: false);
    currentId = 'user-2';
    c.invalidate(membershipUserIdProvider);
    await c.read(membershipOverviewProvider.future);

    final prefs = await SharedPreferences.getInstance();
    final cached1 =
        jsonDecode(
              prefs.getString(MembershipOverviewNotifier.cacheKey('user-1'))!,
            )
            as Map<String, dynamic>;
    final cached2 =
        jsonDecode(
              prefs.getString(MembershipOverviewNotifier.cacheKey('user-2'))!,
            )
            as Map<String, dynamic>;

    expect(cached1['isMember'], isTrue);
    expect(cached2['isMember'], isFalse);
  });
}
