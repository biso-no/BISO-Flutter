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

  @override
  Future<ShopOrder> fetchOrder(String orderId) async {
    fetched.add(orderId);
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

  @override
  Future<MembershipOverview> fetchOverview({bool refresh = false}) async {
    return MembershipOverview(
      state: MembershipGateState.eligible,
      isMember: isMember,
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
    return const StartedCheckout(
      checkoutUrl: 'https://vipps.example/checkout',
      orderId: 'order-1',
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

      expect(
        c.read(membershipCheckoutControllerProvider).phase,
        MembershipPurchasePhase.activationDelayed,
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
}
