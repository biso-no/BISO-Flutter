import 'dart:async';

import 'package:biso/data/models/member_pass.dart';
import 'package:biso/data/services/member_pass_api_client.dart';
import 'package:biso/providers/member_pass/member_pass_provider.dart';
import 'package:biso/providers/member_pass/member_pass_session.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_member_pass_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime.utc(2026, 9, 17, 10).millisecondsSinceEpoch;
  const network = MemberPassApiException(MemberPassApiException.network);

  late FakeMemberPassApi api;
  late StreamController<Object?> connectivity;

  setUp(() {
    api = FakeMemberPassApi();
    connectivity = StreamController<Object?>.broadcast();
  });

  tearDown(() => connectivity.close());

  ProviderContainer container(FakeAsync async, {String? userId = 'u1'}) {
    final c = ProviderContainer(
      overrides: [
        memberPassApiProvider.overrideWithValue(api),
        memberPassClockProvider.overrideWithValue(
          () => t0 + async.elapsed.inMilliseconds,
        ),
        connectivityChangesProvider.overrideWithValue(connectivity.stream),
        membershipUserIdProvider.overrideWithValue(userId),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('fetches once when first listened to and shows the current code', () {
    fakeAsync((async) {
      api.onFetchPass = () => activePassAt(t0);
      final c = container(async);
      c.listen(memberPassProvider, (_, _) {});
      expect(c.read(memberPassProvider).status, PassStatus.loading);

      async.flushMicrotasks();

      expect(api.fetchPassCalls, 1);
      final view = c.read(memberPassProvider);
      expect(view.status, PassStatus.active);
      expect(view.code, 'v1.user-1.${t0 ~/ 30000}.sig');
    });
  });

  test('moves to the next code on its own without refetching', () {
    fakeAsync((async) {
      api.onFetchPass = () => activePassAt(t0);
      final c = container(async);
      c.listen(memberPassProvider, (_, _) {});
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 30));

      expect(
        c.read(memberPassProvider).code,
        'v1.user-1.${t0 ~/ 30000 + 1}.sig',
      );
      expect(api.fetchPassCalls, 1);
    });
  });

  test('refetches when fewer than 4 codes remain', () {
    fakeAsync((async) {
      api.onFetchPass = () => activePassAt(t0, count: 5);
      final c = container(async);
      c.listen(memberPassProvider, (_, _) {});
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 59));
      expect(api.fetchPassCalls, 1);

      api.onFetchPass = () => activePassAt(t0 + 61000);
      async.elapse(const Duration(seconds: 2));
      expect(api.fetchPassCalls, 2);
    });
  });

  test('keeps the pass through a failure and retries every 15 s', () {
    fakeAsync((async) {
      api.onFetchPass = () => activePassAt(t0);
      final c = container(async);
      c.listen(memberPassProvider, (_, _) {});
      async.flushMicrotasks();

      api.onFetchPass = () => throw network;
      c.read(memberPassProvider.notifier).onAppResumed();
      async.flushMicrotasks();
      expect(api.fetchPassCalls, 2);
      expect(c.read(memberPassProvider).status, PassStatus.active);
      expect(c.read(memberPassProvider).offline, isTrue);
      expect(c.read(memberPassProvider).code, isNotNull);

      async.elapse(const Duration(seconds: 14));
      expect(api.fetchPassCalls, 2);
      async.elapse(const Duration(seconds: 1));
      expect(api.fetchPassCalls, 3);

      api.onFetchPass = () => activePassAt(t0 + 15000);
      async.elapse(const Duration(seconds: 15));
      expect(api.fetchPassCalls, 4);
      expect(c.read(memberPassProvider).offline, isFalse);
    });
  });

  test('a first fetch that fails on the network asks to reconnect', () {
    fakeAsync((async) {
      api.onFetchPass = () => throw network;
      final c = container(async);
      c.listen(memberPassProvider, (_, _) {});
      async.flushMicrotasks();
      expect(c.read(memberPassProvider).status, PassStatus.reconnect);
      expect(c.read(memberPassProvider).offline, isTrue);
    });
  });

  test('a 503 on first fetch shows NoPass(unavailable), not reconnect', () {
    fakeAsync((async) {
      api.onFetchPass = () =>
          throw const MemberPassApiException('not_configured', statusCode: 503);
      final c = container(async);
      c.listen(memberPassProvider, (_, _) {});
      async.flushMicrotasks();
      final view = c.read(memberPassProvider);
      expect(view.status, PassStatus.noPass);
      expect(view.noPassState, NoPassState.unavailable);
      expect(view.offline, isFalse);
    });
  });

  test('a 401 shows signed out', () {
    fakeAsync((async) {
      api.onFetchPass = () => activePassAt(t0);
      final c = container(async);
      c.listen(memberPassProvider, (_, _) {});
      async.flushMicrotasks();

      api.onFetchPass = () => throw const MemberPassApiException(
        'not_authenticated',
        statusCode: 401,
      );
      c.read(memberPassProvider.notifier).retry();
      async.flushMicrotasks();

      expect(c.read(memberPassProvider).status, PassStatus.signedOut);
      expect(c.read(memberPassProvider).code, isNull);
    });
  });

  test('a connectivity change fetches', () {
    fakeAsync((async) {
      api.onFetchPass = () => const NoPass(NoPassState.unavailable);
      final c = container(async);
      c.listen(memberPassProvider, (_, _) {});
      async.flushMicrotasks();

      connectivity.add(Object());
      async.flushMicrotasks();

      expect(api.fetchPassCalls, 2);
    });
  });

  test('never runs two fetches at once', () {
    fakeAsync((async) {
      final pending = Completer<MemberPassResponse>();
      api.onFetchPass = () => pending.future;
      final c = container(async);
      c.listen(memberPassProvider, (_, _) {});
      async.flushMicrotasks();
      expect(c.read(memberPassProvider).fetching, isTrue);

      c.read(memberPassProvider.notifier).retry();
      c.read(memberPassProvider.notifier).onAppResumed();
      async.flushMicrotasks();
      expect(api.fetchPassCalls, 1);

      pending.complete(activePassAt(t0));
      async.flushMicrotasks();
      expect(c.read(memberPassProvider).fetching, isFalse);
    });
  });

  test('a hold keeps the codes while no screen listens', () {
    fakeAsync((async) {
      api.onFetchPass = () => activePassAt(t0);
      final c = container(async);
      final sub = c.listen(memberPassProvider, (_, _) {});
      async.flushMicrotasks();

      // Riverpod schedules autoDispose with Future(), a zero-length timer.
      final link = c.read(memberPassProvider.notifier).hold();
      sub.close();
      async.elapse(Duration.zero);
      c.listen(memberPassProvider, (_, _) {}).close();
      async.elapse(Duration.zero);
      expect(api.fetchPassCalls, 1);

      link.close();
      async.elapse(Duration.zero);
      c.listen(memberPassProvider, (_, _) {});
      async.flushMicrotasks();
      expect(api.fetchPassCalls, 2);
    });
  });

  test('without a signed-in user it never asks the server', () {
    fakeAsync((async) {
      final c = container(async, userId: null);
      c.listen(memberPassProvider, (_, _) {});
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1));
      expect(api.fetchPassCalls, 0);
      expect(c.read(memberPassProvider).status, PassStatus.signedOut);
    });
  });
}
