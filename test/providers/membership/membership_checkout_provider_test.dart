import 'dart:async';

import 'package:biso/data/models/membership_overview.dart';
import 'package:biso/data/models/payment_provider.dart';
import 'package:biso/data/models/shop_order.dart';
import 'package:biso/data/services/membership_api_client.dart';
import 'package:biso/data/services/shop_api_client.dart';
import 'package:biso/providers/membership/membership_checkout_provider.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:biso/providers/shop/cart_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeShopApi extends ShopApiClient {
  _FakeShopApi(this.status);

  ShopOrderStatus status;
  final List<String> fetched = [];

  /// When set, every fetch waits for it — so a test can act while a check is
  /// still in flight, the way a student can tap a button while the network
  /// is slow.
  Completer<void>? gate;

  @override
  Future<ShopOrder> fetchOrder(String orderId) async {
    fetched.add(orderId);
    final wait = gate;
    if (wait != null) await wait.future;
    return ShopOrder(
      id: orderId,
      status: status,
      currency: 'NOK',
      subtotal: 550,
      discountTotal: 0,
      total: 550,
      membershipApplied: false,
      memberDiscountPercent: 0,
      items: const [],
    );
  }
}

class _FakeMembershipApi extends MembershipApiClient {
  bool isMember = false;
  MembershipApiException? refuseWith;
  final List<Map<String, String>> started = [];

  /// The order the next `startCheckout` creates.
  String nextOrderId = 'order-1';

  /// How many times the membership was re-checked on demand — the forced
  /// refresh, as opposed to the ordinary load when the overview is built.
  int forcedChecks = 0;

  /// How many of the next forced checks still answer "not a member", the way
  /// the server serves a forced refresh from its cache when it re-checked
  /// the student within the last minute.
  int staleForcedChecks = 0;

  @override
  Future<MembershipOverview> fetchOverview({bool refresh = false}) async {
    var member = isMember;
    if (refresh) {
      forcedChecks++;
      if (staleForcedChecks > 0) {
        staleForcedChecks--;
        member = false;
      }
    }
    return MembershipOverview(
      state: MembershipGateState.eligible,
      isMember: member,
      checkedAt: DateTime.now(),
    );
  }

  @override
  Future<StartedCheckout> startCheckout({
    required PaymentProvider provider,
    required String planId,
    required String campusId,
  }) async {
    final refusal = refuseWith;
    if (refusal != null) throw refusal;
    started.add({
      'provider': provider.id,
      'planId': planId,
      'campusId': campusId,
    });
    return StartedCheckout(
      checkoutUrl: 'https://vipps.example/checkout',
      orderId: nextOrderId,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Uri> launched;
  late bool launchSucceeds;

  ProviderContainer container(
    _FakeShopApi shop,
    _FakeMembershipApi membership,
  ) {
    final c = ProviderContainer(
      overrides: [
        shopApiClientProvider.overrideWithValue(shop),
        membershipApiClientProvider.overrideWithValue(membership),
        membershipUserIdProvider.overrideWithValue('user-1'),
        membershipUrlLauncherProvider.overrideWithValue((uri) async {
          launched.add(uri);
          return launchSucceeds;
        }),
        membershipCheckoutControllerProvider.overrideWith(
          (ref) => MembershipCheckoutController(
            ref,
            activationPollInterval: Duration.zero,
            activationAttempts: 3,
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    launched = [];
    launchSucceeds = true;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'starting a purchase remembers the order and opens the payment provider',
    () async {
      final membership = _FakeMembershipApi();
      final c = container(_FakeShopApi(ShopOrderStatus.pending), membership);

      await c
          .read(membershipCheckoutControllerProvider.notifier)
          .start(provider: PaymentProvider.vipps, planId: '71', campusId: '2');

      expect(membership.started.single, {
        'provider': 'vipps',
        'planId': '71',
        'campusId': '2',
      });
      expect(launched.single.toString(), 'https://vipps.example/checkout');
      expect(
        c.read(membershipCheckoutControllerProvider).phase,
        MembershipPurchasePhase.awaitingPayment,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('membership_pending_order_id'), 'order-1');
    },
  );

  test(
    "a refused purchase shows the server's reason and remembers nothing",
    () async {
      final membership = _FakeMembershipApi()
        ..refuseWith = const MembershipApiException(
          'Your membership already covers this period.',
          statusCode: 409,
        );
      final c = container(_FakeShopApi(ShopOrderStatus.pending), membership);

      await c
          .read(membershipCheckoutControllerProvider.notifier)
          .start(provider: PaymentProvider.vipps, planId: '71', campusId: '2');

      final state = c.read(membershipCheckoutControllerProvider);
      expect(state.phase, MembershipPurchasePhase.failed);
      expect(state.message, 'Your membership already covers this period.');
      expect(launched, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('membership_pending_order_id'), isNull);
    },
  );

  test(
    'a payment completed while the app was closed is picked up at launch and activated',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'membership_pending_order_id': 'order-1',
        'membership_pending_started_at': DateTime.now().millisecondsSinceEpoch,
      });
      final shop = _FakeShopApi(ShopOrderStatus.paid);
      final membership = _FakeMembershipApi()..isMember = true;
      final c = container(shop, membership);

      c.read(membershipCheckoutControllerProvider.notifier);
      await pumpEventQueue();

      expect(shop.fetched, ['order-1']);
      expect(
        c.read(membershipCheckoutControllerProvider).phase,
        MembershipPurchasePhase.activated,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('membership_pending_order_id'), isNull);
    },
  );

  test(
    'a paid order whose membership has not shown up yet says it is on its way',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'membership_pending_order_id': 'order-1',
        'membership_pending_started_at': DateTime.now().millisecondsSinceEpoch,
      });
      final c = container(
        _FakeShopApi(ShopOrderStatus.paid),
        _FakeMembershipApi(),
      );

      c.read(membershipCheckoutControllerProvider.notifier);
      await pumpEventQueue();

      final state = c.read(membershipCheckoutControllerProvider);
      expect(state.phase, MembershipPurchasePhase.activationDelayed);
      expect(
        state.message,
        'Your payment is confirmed. Your membership can take a few minutes '
        'to show up here.',
      );
    },
  );

  test('a stale marker is dropped without asking the server', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'membership_pending_order_id': 'order-1',
      'membership_pending_started_at': DateTime.now()
          .subtract(const Duration(hours: 3))
          .millisecondsSinceEpoch,
    });
    final shop = _FakeShopApi(ShopOrderStatus.paid);
    final c = container(shop, _FakeMembershipApi());

    c.read(membershipCheckoutControllerProvider.notifier);
    await pumpEventQueue();

    expect(shop.fetched, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('membership_pending_order_id'), isNull);
  });

  test('a cancelled return ends the attempt', () async {
    final c = container(
      _FakeShopApi(ShopOrderStatus.pending),
      _FakeMembershipApi(),
    );
    final controller = c.read(membershipCheckoutControllerProvider.notifier);
    await controller.start(
      provider: PaymentProvider.stripe,
      planId: '71',
      campusId: '1',
    );

    await controller.resolvePending(orderId: 'order-1', cancelled: true);

    expect(
      c.read(membershipCheckoutControllerProvider).phase,
      MembershipPurchasePhase.cancelled,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('membership_pending_order_id'), isNull);
  });

  test('a deep link for a different order than the pending one leaves the '
      'marker and state untouched, and the pending order still resolves '
      'afterwards', () async {
    final shop = _FakeShopApi(ShopOrderStatus.paid);
    final membership = _FakeMembershipApi()..isMember = true;
    final c = container(shop, membership);
    final controller = c.read(membershipCheckoutControllerProvider.notifier);
    // Let the (here, no-op — nothing is persisted yet) restore from
    // construction settle before acting, so it cannot land after `start`
    // and see a marker `start` only just wrote. This test is about the
    // different-order guard, not the restore race — that one is covered
    // separately below.
    await pumpEventQueue();
    await controller.start(
      provider: PaymentProvider.vipps,
      planId: '71',
      campusId: '2',
    );
    final stateAfterStart = c.read(membershipCheckoutControllerProvider);
    final prefs = await SharedPreferences.getInstance();

    // 'order-2' is a stale return link for some earlier attempt — not the
    // order 'start' just recorded as pending.
    await controller.resolvePending(orderId: 'order-2');

    expect(shop.fetched, isEmpty);
    expect(c.read(membershipCheckoutControllerProvider), stateAfterStart);
    expect(prefs.getString('membership_pending_order_id'), 'order-1');

    // The order actually pending is unaffected by the stale link and still
    // resolves normally.
    await controller.resolvePending(orderId: 'order-1');

    expect(shop.fetched, ['order-1']);
    expect(
      c.read(membershipCheckoutControllerProvider).phase,
      MembershipPurchasePhase.activated,
    );
    expect(prefs.getString('membership_pending_order_id'), isNull);
  });

  test('a deep link that arrives before the restore has completed still '
      'resolves that order correctly', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'membership_pending_order_id': 'order-1',
      'membership_pending_started_at': DateTime.now().millisecondsSinceEpoch,
    });
    final shop = _FakeShopApi(ShopOrderStatus.paid);
    final membership = _FakeMembershipApi()..isMember = true;
    final c = container(shop, membership);

    final controller = c.read(membershipCheckoutControllerProvider.notifier);
    // No pump between construction and this call: the constructor's own
    // restore of the persisted marker is still in flight when the deep
    // link's resolve lands, exactly as a cold launch straight into the
    // return deep link races the marker being read back from disk.
    await controller.resolvePending(orderId: 'order-1');
    await pumpEventQueue();

    expect(shop.fetched, ['order-1']);
    expect(
      c.read(membershipCheckoutControllerProvider).phase,
      MembershipPurchasePhase.activated,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('membership_pending_order_id'), isNull);
  });

  test(
    'an unopened payment provider is reported, and the order stays resumable',
    () async {
      launchSucceeds = false;
      final c = container(
        _FakeShopApi(ShopOrderStatus.pending),
        _FakeMembershipApi(),
      );

      await c
          .read(membershipCheckoutControllerProvider.notifier)
          .start(provider: PaymentProvider.vipps, planId: '71', campusId: '2');

      final state = c.read(membershipCheckoutControllerProvider);
      expect(state.phase, MembershipPurchasePhase.failed);
      expect(state.message, 'We could not open your payment provider.');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('membership_pending_order_id'), 'order-1');
    },
  );

  test(
    'starting over forgets the payment on disk, not just on screen',
    () async {
      final membership = _FakeMembershipApi();
      final shop = _FakeShopApi(ShopOrderStatus.pending);
      final c = container(shop, membership);
      final controller = c.read(membershipCheckoutControllerProvider.notifier);
      await pumpEventQueue();
      await controller.start(
        provider: PaymentProvider.vipps,
        planId: '71',
        campusId: '2',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('membership_pending_order_id'), 'order-1');

      await controller.abandonPending();

      expect(
        c.read(membershipCheckoutControllerProvider).phase,
        MembershipPurchasePhase.idle,
      );
      expect(prefs.getString('membership_pending_order_id'), isNull);
      expect(prefs.getInt('membership_pending_started_at'), isNull);

      // A relaunch reads the marker back from disk; with it gone, there is
      // nothing to follow and nothing is fetched.
      final relaunched = container(shop, membership);
      relaunched.read(membershipCheckoutControllerProvider.notifier);
      await pumpEventQueue();
      expect(shop.fetched, isEmpty);
      expect(
        relaunched.read(membershipCheckoutControllerProvider).phase,
        MembershipPurchasePhase.idle,
      );
    },
  );

  test('a check still in flight when the student starts over changes '
      'nothing once it lands', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'membership_pending_order_id': 'order-1',
      'membership_pending_started_at': DateTime.now().millisecondsSinceEpoch,
    });
    // The order is still pending server-side: applied, this answer would put
    // "Waiting for your payment" back and lock the Pay button again.
    final shop = _FakeShopApi(ShopOrderStatus.pending)
      ..gate = Completer<void>();
    final c = container(shop, _FakeMembershipApi());
    final controller = c.read(membershipCheckoutControllerProvider.notifier);
    await pumpEventQueue();
    expect(shop.fetched, ['order-1'], reason: 'the launch check is in flight');

    await controller.abandonPending();
    final prefs = await SharedPreferences.getInstance();
    // Everything on disk except the membership overview's own cache, which
    // the re-check that "Start over" asks for rightly refreshes.
    Map<String, Object?> storage() => {
      for (final key in prefs.getKeys())
        if (!key.startsWith('membership_overview_v1_')) key: prefs.get(key),
    };
    final stored = storage();

    shop.gate!.complete();
    await pumpEventQueue();

    expect(
      c.read(membershipCheckoutControllerProvider),
      const MembershipPurchaseState(),
    );
    expect(storage(), stored);
    expect(prefs.getString('membership_pending_order_id'), isNull);
  });

  for (final status in [ShopOrderStatus.failed, ShopOrderStatus.paid]) {
    test('a check that lands after a new attempt started leaves that attempt '
        'alone (${status.name})', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'membership_pending_order_id': 'order-1',
        'membership_pending_started_at': DateTime.now().millisecondsSinceEpoch,
      });
      // Applied, this answer would replace order-2's state and clear its
      // marker, whether the abandoned order failed or was paid.
      final shop = _FakeShopApi(status)..gate = Completer<void>();
      final membership = _FakeMembershipApi()..nextOrderId = 'order-2';
      final c = container(shop, membership);
      final controller = c.read(membershipCheckoutControllerProvider.notifier);
      await pumpEventQueue();

      await controller.abandonPending();
      await controller.start(
        provider: PaymentProvider.vipps,
        planId: '71',
        campusId: '2',
      );
      final pending = c.read(membershipCheckoutControllerProvider);
      expect(pending.phase, MembershipPurchasePhase.awaitingPayment);
      expect(pending.orderId, 'order-2');

      shop.gate!.complete();
      await pumpEventQueue();

      expect(c.read(membershipCheckoutControllerProvider), pending);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('membership_pending_order_id'), 'order-2');
    });
  }

  test('starting over re-checks the membership, in case that payment went '
      'through', () async {
    final membership = _FakeMembershipApi();
    final c = container(_FakeShopApi(ShopOrderStatus.pending), membership);
    final controller = c.read(membershipCheckoutControllerProvider.notifier);
    await pumpEventQueue();
    await controller.start(
      provider: PaymentProvider.vipps,
      planId: '71',
      campusId: '2',
    );
    final before = membership.forcedChecks;

    await controller.abandonPending();
    await pumpEventQueue();

    expect(membership.forcedChecks, before + 1);
  });

  test('a return link for an order that is not the pending one re-checks '
      'the membership instead', () async {
    final shop = _FakeShopApi(ShopOrderStatus.paid);
    final membership = _FakeMembershipApi();
    final c = container(shop, membership);
    final controller = c.read(membershipCheckoutControllerProvider.notifier);
    expect(
      (await c.read(membershipOverviewProvider.future))?.isMember,
      isFalse,
    );
    await controller.start(
      provider: PaymentProvider.vipps,
      planId: '71',
      campusId: '2',
    );
    final before = membership.forcedChecks;

    // The student abandoned 'order-0', started 'order-1', and then paid
    // 'order-0' after all: its return link arrives while 'order-1' is the
    // one pending, and the server now has them as a member.
    membership.isMember = true;
    await controller.resolvePending(orderId: 'order-0');
    await pumpEventQueue();

    expect(shop.fetched, isEmpty);
    expect(membership.forcedChecks, before + 1);
    // The re-check is what shows the membership that was paid for — and,
    // with it, stops the server offering a plan to pay for again.
    expect(c.read(membershipOverviewProvider).valueOrNull?.isMember, isTrue);
  });

  test('a paid order that comes back after starting over is still shown '
      'landing', () async {
    final shop = _FakeShopApi(ShopOrderStatus.paid);
    final membership = _FakeMembershipApi();
    final c = container(shop, membership);
    final controller = c.read(membershipCheckoutControllerProvider.notifier);
    await pumpEventQueue();
    await controller.start(
      provider: PaymentProvider.vipps,
      planId: '71',
      campusId: '2',
    );
    await controller.abandonPending();
    await pumpEventQueue();

    // The student paid the order they walked away from after all — the
    // waiting banner invites exactly that. The server has them as a member,
    // but "Start over" used up its one-minute refresh window, so the next
    // two forced checks still answer from its cache.
    membership
      ..isMember = true
      ..staleForcedChecks = 2;
    final phases = <MembershipPurchasePhase>[];
    c.listen(
      membershipCheckoutControllerProvider,
      (_, next) => phases.add(next.phase),
    );
    await controller.resolvePending(orderId: 'order-1');
    await pumpEventQueue();

    expect(shop.fetched, ['order-1']);
    expect(phases, [
      MembershipPurchasePhase.activating,
      MembershipPurchasePhase.activated,
    ]);
    expect(
      c.read(membershipCheckoutControllerProvider),
      const MembershipPurchaseState(
        phase: MembershipPurchasePhase.activated,
        orderId: 'order-1',
      ),
    );
    // There was no marker to clear, and none is written.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('membership_pending_order_id'), isNull);
    expect(prefs.getInt('membership_pending_started_at'), isNull);
  });

  test('a paid return link for an attempt whose marker expired is still '
      'shown landing', () async {
    // The marker lasts two hours; a card checkout session can last a day.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'membership_pending_order_id': 'order-1',
      'membership_pending_started_at': DateTime.now()
          .subtract(const Duration(hours: 3))
          .millisecondsSinceEpoch,
    });
    final shop = _FakeShopApi(ShopOrderStatus.paid);
    final membership = _FakeMembershipApi()..isMember = true;
    final c = container(shop, membership);
    final controller = c.read(membershipCheckoutControllerProvider.notifier);
    await pumpEventQueue();
    expect(shop.fetched, isEmpty, reason: 'nothing is followed on its own');

    await controller.resolvePending(orderId: 'order-1');
    await pumpEventQueue();

    expect(shop.fetched, ['order-1']);
    expect(
      c.read(membershipCheckoutControllerProvider).phase,
      MembershipPurchasePhase.activated,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('membership_pending_order_id'), isNull);
  });

  for (final status in [
    ShopOrderStatus.pending,
    ShopOrderStatus.failed,
    ShopOrderStatus.cancelled,
    ShopOrderStatus.refunded,
  ]) {
    test('an unpaid (${status.name}) order that comes back after starting '
        'over is left alone', () async {
      final shop = _FakeShopApi(status);
      final membership = _FakeMembershipApi();
      final c = container(shop, membership);
      final controller = c.read(membershipCheckoutControllerProvider.notifier);
      await pumpEventQueue();
      await controller.start(
        provider: PaymentProvider.vipps,
        planId: '71',
        campusId: '2',
      );
      await controller.abandonPending();
      await pumpEventQueue();
      final before = membership.forcedChecks;

      await controller.resolvePending(orderId: 'order-1');
      await pumpEventQueue();

      // The student gave that attempt up, and nothing about it changed that:
      // the screen stays ready for a new one. The membership is still
      // re-checked, and the read has had the server reconcile the order.
      expect(shop.fetched, ['order-1']);
      expect(
        c.read(membershipCheckoutControllerProvider),
        const MembershipPurchaseState(),
      );
      expect(membership.forcedChecks, before + 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('membership_pending_order_id'), isNull);
    });
  }
}
