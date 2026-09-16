import 'package:biso/data/models/membership_overview.dart';
import 'package:biso/data/models/payment_provider.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/presentation/screens/profile/membership_screen.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/membership/membership_checkout_provider.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:biso/providers/shop/checkout_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/biso_screen_harness.dart';

const _user = UserModel(
  id: 'u1',
  name: 'Ola Nordmann',
  email: 'ola@example.com',
);

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth() : super(const AuthState(isAuthenticated: true, user: _user));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixedOverview extends MembershipOverviewNotifier {
  _FixedOverview(this.value);

  final MembershipOverview? value;
  int refreshes = 0;
  bool linkNoted = false;

  @override
  Future<MembershipOverview?> build() async => value;

  @override
  Future<void> refresh({bool force = true}) async => refreshes++;

  @override
  void noteLinkStarted() => linkNoted = true;
}

class _RecordingCheckout extends MembershipCheckoutController {
  _RecordingCheckout(super.ref);

  final List<String> started = [];

  /// Explicit `resolvePending(orderId: ..., cancelled: ...)` calls, as
  /// `_handleArrival` makes them for a payment return. The base
  /// controller's own constructor also calls `resolvePending()` once with no
  /// arguments (the "cold launch is not a resume" check), which is not an
  /// arrival and is not what a test asserting on an arrival cares about, so
  /// only calls that name an order are recorded here.
  final List<(String, bool)> resolved = [];

  @override
  Future<void> start({
    required PaymentProvider provider,
    required String planId,
    required String campusId,
  }) async {
    started.add('${provider.id}:$planId:$campusId');
  }

  @override
  Future<void> resolvePending({String? orderId, bool cancelled = false}) async {
    if (orderId != null) resolved.add((orderId, cancelled));
  }

  /// Drives `_PurchaseBanner` directly from a test, without a real payment.
  void setPhase(MembershipPurchaseState value) => state = value;
}

final _plan = MembershipPlanOption(
  id: '71',
  name: 'BISO Membership fall 2026 and spring 2027',
  price: 550,
  duration: 'year',
  accrualMonths: 12,
  expiryDate: DateTime(2027, 6, 30),
);

MembershipOverview _overview({
  required MembershipGateState state,
  bool isMember = false,
  List<MembershipPlanOption> plans = const [],
}) => MembershipOverview(
  state: state,
  isMember: isMember,
  studentId: state == MembershipGateState.needsBiLink ? null : 's1715738',
  checkedAt: DateTime.now(),
  memberships: isMember
      ? [
          MembershipPeriod(
            id: '71',
            name: 'BISO Membership fall 2026 and spring 2027',
            expiryDate: DateTime(2027, 6, 30),
          ),
        ]
      : const [],
  offeredPlans: plans,
  defaultCampusId: '2',
  campuses: const [
    MembershipCampus(id: '1', name: 'Oslo'),
    MembershipCampus(id: '2', name: 'Bergen'),
  ],
);

void main() {
  late _FixedOverview overview;
  late _RecordingCheckout checkout;
  late List<Uri> launched;

  List<Override> overrides(MembershipOverview? value) {
    overview = _FixedOverview(value);
    return [
      authStateProvider.overrideWith((_) => _Auth()),
      membershipOverviewProvider.overrideWith(() => overview),
      membershipCheckoutControllerProvider.overrideWith(
        (ref) => checkout = _RecordingCheckout(ref),
      ),
      membershipUrlLauncherProvider.overrideWithValue((uri) async {
        launched.add(uri);
        return true;
      }),
      availablePaymentProvidersProvider.overrideWithValue(
        const AsyncData([PaymentProvider.vipps, PaymentProvider.stripe]),
      ),
    ];
  }

  setUp(() {
    launched = [];
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('builds on BisoPage in every appearance', (tester) async {
    await expectBuildsCleanly(
      tester,
      () => const MembershipScreen(),
      overrides: overrides(
        _overview(state: MembershipGateState.eligible, plans: [_plan]),
      ),
    );
  });

  testWidgets('an unlinked student is sent to biso.no to link', (tester) async {
    await pumpBisoScreen(
      tester,
      const MembershipScreen(),
      overrides: overrides(_overview(state: MembershipGateState.needsBiLink)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Link your BI student account'), findsOneWidget);
    await tester.tap(find.text('Link on biso.no'));
    await tester.pumpAndSettle();

    expect(launched.single.toString(), 'https://biso.no/membership/link');
    expect(overview.linkNoted, isTrue);
  });

  testWidgets('a member sees their membership and its expiry', (tester) async {
    await pumpBisoScreen(
      tester,
      const MembershipScreen(),
      overrides: overrides(
        _overview(state: MembershipGateState.alreadyMember, isMember: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Active member'), findsOneWidget);
    expect(
      find.text('BISO Membership fall 2026 and spring 2027'),
      findsOneWidget,
    );
    expect(find.text('Valid until'), findsOneWidget);
    expect(find.text('Pay NOK 550 with Vipps'), findsNothing);
  });

  testWidgets(
    'an eligible student picks a plan and pays with an enabled provider',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const MembershipScreen(),
        overrides: overrides(
          _overview(state: MembershipGateState.eligible, plans: [_plan]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bergen'), findsOneWidget);
      // The pay button sits below the fold of this long form — the same as a
      // real device — so jump the page's own scroll view to the bottom first,
      // mirroring `_pageScrollable` in cart_checkout_design_test.dart. Without
      // it, `find.text` (skipOffstage: true by default) reports zero matches
      // for a button that has never been painted, and `ensureVisible` has
      // nothing to scroll.
      final pageScrollable = find
          .byType(Scrollable)
          .evaluate()
          .map(
            (element) => (element as StatefulElement).state as ScrollableState,
          )
          .reduce(
            (a, b) =>
                a.position.maxScrollExtent > b.position.maxScrollExtent ? a : b,
          );
      pageScrollable.position.jumpTo(pageScrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();

      final pay = find.text('Pay NOK 550 with Vipps');
      await tester.ensureVisible(pay);
      await tester.tap(pay);
      await tester.pumpAndSettle();

      expect(checkout.started, ['vipps:71:2']);
    },
  );

  testWidgets('an unverifiable check offers a retry', (tester) async {
    await pumpBisoScreen(
      tester,
      const MembershipScreen(),
      overrides: overrides(
        _overview(state: MembershipGateState.checkUnavailable),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    await tester.pumpAndSettle();

    expect(overview.refreshes, 1);
  });

  testWidgets('returning from biso.no re-checks straight away', (tester) async {
    await pumpBisoScreen(
      tester,
      const MembershipScreen(linked: true),
      overrides: overrides(_overview(state: MembershipGateState.needsBiLink)),
    );
    await tester.pumpAndSettle();

    expect(overview.refreshes, 1);
  });

  testWidgets('a payment return resolves the order it names', (tester) async {
    await pumpBisoScreen(
      tester,
      const MembershipScreen(returnedOrderId: 'order-1'),
      overrides: overrides(_overview(state: MembershipGateState.needsBiLink)),
    );
    await tester.pumpAndSettle();

    expect(checkout.resolved, [('order-1', false)]);
  });

  testWidgets('a cancelled payment return passes the cancellation through', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const MembershipScreen(
        returnedOrderId: 'order-1',
        returnedCancelled: true,
      ),
      overrides: overrides(_overview(state: MembershipGateState.needsBiLink)),
    );
    await tester.pumpAndSettle();

    expect(checkout.resolved, [('order-1', true)]);
  });

  testWidgets(
    'an activation-delayed banner shows the message a student actually reads',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const MembershipScreen(),
        overrides: overrides(_overview(state: MembershipGateState.needsBiLink)),
      );
      await tester.pumpAndSettle();

      // The exact wording MembershipCheckoutController._activate() sets, so
      // this pins what the student actually reads while their membership
      // has not shown up yet — the moment they are most likely to think
      // something went wrong.
      checkout.setPhase(
        const MembershipPurchaseState(
          phase: MembershipPurchasePhase.activationDelayed,
          orderId: 'order-1',
          message:
              'Your payment is confirmed. Your membership can take a few '
              'minutes to show up here.',
        ),
      );
      await tester.pump();

      expect(find.text('Payment confirmed'), findsOneWidget);
      expect(
        find.text(
          'Your payment is confirmed. Your membership can take a few '
          'minutes to show up here.',
        ),
        findsOneWidget,
      );
    },
  );
}
