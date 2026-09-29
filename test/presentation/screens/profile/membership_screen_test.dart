import 'package:biso/data/models/membership_overview.dart';
import 'package:biso/data/models/payment_provider.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/presentation/screens/profile/membership_screen.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/membership/membership_checkout_provider.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/shop/checkout_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/biso_screen_harness.dart';
import '../../../helpers/membership_fixtures.dart';

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

  testWidgets(
    'a student who walked away from a payment can start over and pay again',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const MembershipScreen(),
        overrides: overrides(
          _overview(state: MembershipGateState.eligible, plans: [_plan]),
        ),
      );
      await tester.pumpAndSettle();

      // The student opened Vipps and never came back: the order is still
      // pending server-side, so the screen is waiting.
      checkout.setPhase(
        const MembershipPurchaseState(
          phase: MembershipPurchasePhase.awaitingPayment,
          orderId: 'order-1',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Waiting for your payment'), findsOneWidget);
      expect(_payButton(tester).onPressed, isNull);

      await tester.tap(find.text('Start over'));
      await tester.pumpAndSettle();

      // The banner is gone and the plan can be paid for again — without the
      // app ever claiming the abandoned order was cancelled.
      expect(find.text('Waiting for your payment'), findsNothing);
      expect(find.text('Payment cancelled'), findsNothing);
      expect(_payButton(tester).onPressed, isNotNull);

      _scrollPageToBottom(tester);
      await tester.pumpAndSettle();
      final pay = find.text('Pay NOK 550 with Vipps');
      await tester.ensureVisible(pay);
      await tester.tap(pay);
      await tester.pumpAndSettle();

      expect(checkout.started, ['vipps:71:2']);
    },
  );

  testWidgets('no plans on sale points the student at BISO, not BI', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const MembershipScreen(),
      overrides: overrides(
        _overview(state: MembershipGateState.noPlansAvailable),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Membership isn't on sale right now"), findsOneWidget);
    expect(find.textContaining('get in touch with BISO'), findsOneWidget);
    // The BI student app does not sell BISO memberships, so it must not be
    // offered as a way in.
    expect(find.textContaining('BI student app'), findsNothing);
  });

  group('plans after BISO-Sites PR #83', () {
    // Tall enough that the whole purchase form is on screen at once.
    const tall = Size(390, 2400);

    Future<void> pump(WidgetTester tester, MembershipOverview value) async {
      await pumpBisoScreen(
        tester,
        const MembershipScreen(),
        overrides: overrides(value),
        size: tall,
      );
      await tester.pumpAndSettle();
    }

    Finder row(String title) => find.byWidgetPredicate(
      (widget) => widget is BisoListRow && widget.title == title,
    );

    String? subtitleOf(WidgetTester tester, String title) =>
        tester.widget<BisoListRow>(row(title)).subtitle;

    Future<void> pay(WidgetTester tester, String label) async {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    testWidgets('29 Sep, non-member: one row per duration and no choice', (
      tester,
    ) async {
      await pump(
        tester,
        membershipOverviewOf(
          plans: [fall2026Semester, fall2026Year, fall2026ThreeYears],
        ),
      );

      expect(row('Semester'), findsOneWidget);
      expect(row('1 year'), findsOneWidget);
      expect(row('3 years'), findsOneWidget);
      expect(
        subtitleOf(tester, 'Semester'),
        'NOK 350 · valid until December 31, 2026',
      );
      expect(find.textContaining('BISO Membership product'), findsNothing);
      expect(find.textContaining('This membership ends'), findsNothing);
    });

    testWidgets('10 Dec, non-member: Semester offers next semester, and that '
        'is the plan paid for', (tester) async {
      await pump(
        tester,
        membershipOverviewOf(
          plans: [
            fall2026Semester,
            fall2026Year,
            fall2026ThreeYears,
            spring2027Semester,
            spring2027Year,
            spring2027ThreeYears,
          ],
        ),
      );

      // Six plans on offer, still one row per duration.
      expect(row('Semester'), findsOneWidget);
      expect(row('1 year'), findsOneWidget);
      expect(row('3 years'), findsOneWidget);
      expect(
        find.text('This membership ends December 31, 2026.'),
        findsOneWidget,
      );
      expect(
        find.text('Buy for this semester (until December 31, 2026)'),
        findsOneWidget,
      );

      await tester.tap(
        find.text(
          'Start next semester instead (January 1, 2027 – June 30, 2027)',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        subtitleOf(tester, 'Semester'),
        'NOK 350 · January 1, 2027 – June 30, 2027',
      );
      await pay(tester, 'Pay NOK 350 with Vipps');
      expect(checkout.started, ['vipps:60:2']);
    });

    testWidgets('changing the duration resets the choice to this semester', (
      tester,
    ) async {
      await pump(
        tester,
        membershipOverviewOf(
          plans: [
            fall2026Semester,
            fall2026Year,
            spring2027Semester,
            spring2027Year,
          ],
        ),
      );

      await tester.tap(
        find.text(
          'Start next semester instead (January 1, 2027 – June 30, 2027)',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(row('1 year'));
      await tester.pumpAndSettle();

      expect(
        subtitleOf(tester, '1 year'),
        'NOK 550 · valid until June 30, 2027',
      );
      await pay(tester, 'Pay NOK 550 with Vipps');
      expect(checkout.started, ['vipps:55:2']);
    });

    testWidgets('13 Dec, holds only spring 2027: says when it starts and does '
        'not offer Semester again', (tester) async {
      await pump(
        tester,
        membershipOverviewOf(
          upcoming: [spring2027Semester],
          currentExpiry: DateTime(2027, 6, 30),
          plans: [spring2027Year, spring2027ThreeYears],
        ),
      );

      expect(find.text('Upcoming membership'), findsOneWidget);
      expect(
        find.text(
          'Your membership starts January 1, 2027 and runs until June 30, '
          '2027. Benefits become available from the start date.',
        ),
        findsOneWidget,
      );
      expect(row('Semester'), findsNothing);
      expect(find.textContaining('This membership ends'), findsNothing);
    });

    testWidgets('already_member with only an upcoming membership is not '
        '"already a member"', (tester) async {
      await pump(
        tester,
        membershipOverviewOf(
          state: MembershipGateState.alreadyMember,
          upcoming: [spring2027Semester],
          currentExpiry: DateTime(2027, 6, 30),
        ),
      );

      expect(
        find.text(
          'Your membership starts January 1, 2027 and runs until June 30, '
          '2027. Benefits become available from the start date.',
        ),
        findsOneWidget,
      );
      expect(find.text('Active member'), findsNothing);
      expect(find.text('Become a member'), findsNothing);
    });

    testWidgets('15 Oct, fall semester member: Semester is next spring with no '
        'choice, the longer plans start now', (tester) async {
      await pump(
        tester,
        membershipOverviewOf(
          isMember: true,
          active: [fall2026Semester],
          currentExpiry: DateTime(2026, 12, 31),
          plans: [spring2027Semester, fall2026Year, fall2026ThreeYears],
        ),
      );

      expect(find.text('Active member'), findsOneWidget);
      expect(
        subtitleOf(tester, 'Semester'),
        'NOK 350 · January 1, 2027 – June 30, 2027',
      );
      expect(
        subtitleOf(tester, '1 year'),
        'NOK 550 · valid until June 30, 2027',
      );
      expect(find.textContaining('This membership ends'), findsNothing);
      await pay(tester, 'Pay NOK 350 with Vipps');
      expect(checkout.started, ['vipps:60:2']);
    });

    testWidgets('a purchase for next semester says when it starts', (
      tester,
    ) async {
      await pump(tester, membershipOverviewOf());

      checkout.setPhase(
        MembershipPurchaseState(
          phase: MembershipPurchasePhase.activated,
          orderId: 'order-1',
          startsOn: DateTime.utc(2027, 1, 1),
        ),
      );
      await tester.pump();

      expect(
        find.text(
          'Your membership starts January 1, 2027. Benefits become available '
          'from the start date.',
        ),
        findsOneWidget,
      );
      expect(find.text("You're a member now."), findsNothing);
    });

    testWidgets('a purchase that has started says so', (tester) async {
      await pump(tester, membershipOverviewOf());

      checkout.setPhase(
        const MembershipPurchaseState(
          phase: MembershipPurchasePhase.activated,
          orderId: 'order-1',
        ),
      );
      await tester.pump();

      expect(find.text("You're a member now."), findsOneWidget);
    });

    testWidgets('dates follow the app language', (tester) async {
      await pumpBisoScreen(
        tester,
        const MembershipScreen(),
        overrides: overrides(
          membershipOverviewOf(plans: [fall2026Semester, spring2027Semester]),
        ),
        size: tall,
        locale: const Locale('no'),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Dette medlemskapet slutter 31. desember 2026.'),
        findsOneWidget,
      );
    });
  });
}

/// The membership screen's own scroll view — the tallest one on screen, as
/// in `cart_checkout_design_test.dart`. The pay button sits below the fold of
/// this long form, so a test that never scrolls finds nothing to tap.
void _scrollPageToBottom(WidgetTester tester) {
  final pageScrollable = find
      .byType(Scrollable)
      .evaluate()
      .map((element) => (element as StatefulElement).state as ScrollableState)
      .reduce(
        (a, b) =>
            a.position.maxScrollExtent > b.position.maxScrollExtent ? a : b,
      );
  pageScrollable.position.jumpTo(pageScrollable.position.maxScrollExtent);
}

/// The pay button, found without scrolling: whether it is enabled is what
/// decides if a student is locked out, and `skipOffstage: false` reads it
/// even while it is below the fold.
FilledButton _payButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.byType(FilledButton, skipOffstage: false).last,
);
