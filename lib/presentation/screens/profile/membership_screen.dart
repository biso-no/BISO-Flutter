import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/currency.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../core/utils/oslo_time.dart';
import '../../../data/models/membership_overview.dart';
import '../../../data/models/payment_provider.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/membership/membership_checkout_provider.dart';
import '../../../providers/membership/membership_overview_provider.dart';
import '../../../providers/shop/checkout_provider.dart';
import '../../widgets/biso/biso.dart';
import '../../widgets/member_pass/member_pass_row.dart';

/// Where a student links their BI account. BI's tenant is reachable only
/// through Appwrite's OIDC provider, in a browser holding the student's own
/// biso.no session, so the app hands this step to the website.
final membershipLinkUrl = Uri.parse('https://biso.no/membership/link');

String _formatDate(DateTime? date) =>
    date == null ? '' : DateFormat.yMMMd().format(date);

/// A membership date as the student reads it: long, in the app's language,
/// and always the Oslo calendar day.
String _longDate(BuildContext context, DateTime? date) => date == null
    ? ''
    : formatOsloDate(date, AppLocalizations.of(context)!.localeName);

/// A plan row's label. The plan's own name is the 24SevenOffice product
/// name and is never shown.
String _durationLabel(AppLocalizations l10n, MembershipPlanOption plan) =>
    switch (plan.duration) {
      'semester' => l10n.membershipDurationSemester,
      'year' => l10n.membershipDurationYear,
      'three_years' => l10n.membershipDurationThreeYears,
      _ => l10n.membershipDurationMonths(plan.accrualMonths),
    };

/// Price and dates of [plan]. A plan starting next season says when it
/// starts; one starting now only when it ends.
String _planSummary(BuildContext context, MembershipPlanOption plan) {
  final l10n = AppLocalizations.of(context)!;
  final price = formatNok(plan.price);
  final end = _longDate(context, plan.expiryDate);
  if (plan.offer == MembershipPlanOffer.next && plan.startDate != null) {
    return l10n.membershipPlanPeriod(
      price,
      _longDate(context, plan.startDate),
      end,
    );
  }
  return l10n.membershipPlanValidUntil(price, end);
}

/// The student's BISO membership: verified status, BI linking, and purchase.
///
/// Status comes from `GET /api/membership`, which reads 24SevenOffice. Buying
/// goes through the trusted membership checkout; the payment is followed home
/// by [MembershipCheckoutController].
class MembershipScreen extends ConsumerStatefulWidget {
  const MembershipScreen({
    super.key,
    this.returnedOrderId,
    this.returnedCancelled = false,
    this.linked = false,
  });

  /// Set when the payment provider sent the student back here.
  final String? returnedOrderId;
  final bool returnedCancelled;

  /// Set when biso.no sent the student back after linking.
  final bool linked;

  @override
  ConsumerState<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends ConsumerState<MembershipScreen> {
  /// The duration row picked; null means the first one offered.
  String? _duration;

  /// The student chose to start next season instead of this one. Only
  /// meaningful while the picked duration offers both.
  bool _startNext = false;
  String? _campusId;
  PaymentProvider? _provider;

  @override
  void initState() {
    super.initState();
    _handleArrival();
  }

  @override
  void didUpdateWidget(covariant MembershipScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.returnedOrderId != widget.returnedOrderId ||
        oldWidget.returnedCancelled != widget.returnedCancelled ||
        oldWidget.linked != widget.linked) {
      _handleArrival();
    }
  }

  /// Acts on a return link: verify the payment it names, or re-check the
  /// membership after a BI link.
  void _handleArrival() {
    final orderId = widget.returnedOrderId;
    final cancelled = widget.returnedCancelled;
    final linked = widget.linked;
    if (orderId == null && !linked) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (orderId != null) {
        ref
            .read(membershipCheckoutControllerProvider.notifier)
            .resolvePending(orderId: orderId, cancelled: cancelled);
      } else {
        ref.read(membershipOverviewProvider.notifier).refresh();
      }
    });
  }

  Future<void> _openLinkPage() async {
    ref.read(membershipOverviewProvider.notifier).noteLinkStarted();
    final opened = await ref.read(membershipUrlLauncherProvider)(
      membershipLinkUrl,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We could not open biso.no. Please try again.'),
        ),
      );
    }
  }

  Future<void> _refresh() =>
      ref.read(membershipOverviewProvider.notifier).refresh();

  @override
  Widget build(BuildContext context) {
    final leading = BisoBackButton(
      onPressed: () =>
          NavigationUtils.safeGoBack(context, fallbackRoute: '/profile'),
    );
    final isAuthenticated = ref.watch(
      authStateProvider.select((state) => state.isAuthenticated),
    );

    if (!isAuthenticated) {
      return BisoPage(
        title: 'Membership',
        leading: leading,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoEmptyState(
              icon: CupertinoIcons.lock,
              accent: BisoAccent.gold,
              title: 'Sign in to see your membership',
              message: 'Your BISO membership is tied to your BISO account.',
              action: FilledButton(
                onPressed: () => context.go('/auth/login'),
                child: const Text('Sign in'),
              ),
            ),
          ),
        ],
      );
    }

    final overviewAsync = ref.watch(membershipOverviewProvider);
    final overview = overviewAsync.valueOrNull;
    final purchase = ref.watch(membershipCheckoutControllerProvider);

    if (overview == null) {
      return BisoPage(
        title: 'Membership',
        leading: leading,
        onRefresh: _refresh,
        slivers: [
          if (overviewAsync.hasError)
            SliverFillRemaining(
              hasScrollBody: false,
              child: BisoEmptyState(
                icon: CupertinoIcons.exclamationmark_triangle,
                title: 'We could not check your membership',
                message: 'Check your connection and try again.',
                action: FilledButton(
                  onPressed: _refresh,
                  child: const Text('Try again'),
                ),
              ),
            )
          else
            const SliverToBoxAdapter(child: BisoSkeleton.card()),
        ],
      );
    }

    final email = ref.watch(
      authStateProvider.select((state) => state.user?.email ?? ''),
    );
    final controller = ref.read(membershipCheckoutControllerProvider.notifier);

    return BisoPage(
      title: 'Membership',
      leading: leading,
      onRefresh: _refresh,
      slivers: [
        if (purchase.phase != MembershipPurchasePhase.idle)
          SliverToBoxAdapter(
            child: _PurchaseBanner(
              state: purchase,
              onCheckAgain: () => controller.resolvePending(),
              onStartOver: controller.abandonPending,
              onDismiss: controller.dismissOutcome,
            ),
          ),
        SliverToBoxAdapter(
          child: overview.isMember
              ? _MembershipCard(overview: overview)
              : _NotMemberCard(
                  overview: overview,
                  email: email,
                  onLink: _openLinkPage,
                  onRetry: _refresh,
                ),
        ),
        if (overview.canPurchase) ..._purchaseSlivers(overview, purchase),
      ],
    );
  }

  List<Widget> _purchaseSlivers(
    MembershipOverview overview,
    MembershipPurchaseState purchase,
  ) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    final l10n = AppLocalizations.of(context)!;
    final choices = overview.planChoices;
    final choice =
        choices.where((c) => c.duration == _duration).firstOrNull ??
        choices.firstOrNull;
    final plan = choice?.plan(startNext: _startNext);
    final campusId =
        _campusId ??
        overview.defaultCampusId ??
        overview.campuses.firstOrNull?.id;
    final providers = ref.watch(availablePaymentProvidersProvider);
    final available = providers.valueOrNull ?? const <PaymentProvider>[];
    final provider = available.contains(_provider)
        ? _provider
        : available.firstOrNull;
    final busy = const {
      MembershipPurchasePhase.starting,
      MembershipPurchasePhase.awaitingPayment,
      MembershipPurchasePhase.activating,
    }.contains(purchase.phase);

    final selectedPlan = plan;
    final selectedCampus = campusId;
    final selectedProvider = provider;
    VoidCallback? onPay;
    if (selectedPlan != null &&
        selectedCampus != null &&
        selectedProvider != null &&
        !busy) {
      onPay = () => ref
          .read(membershipCheckoutControllerProvider.notifier)
          .start(
            provider: selectedProvider,
            planId: selectedPlan.id,
            campusId: selectedCampus,
          );
    }

    void pickDuration(String duration) => setState(() {
      _duration = duration;
      _startNext = false;
    });

    final current = choice?.current;
    final next = choice?.next;

    return [
      SliverToBoxAdapter(
        child: RadioGroup<String>(
          groupValue: choice?.duration,
          onChanged: (duration) {
            if (duration != null) pickDuration(duration);
          },
          child: BisoFormGroup(
            title: overview.isMember
                ? 'Extend your membership'
                : 'Choose a membership',
            children: [
              for (final option in choices)
                BisoListRow(
                  leading: const BisoIconTile(
                    icon: CupertinoIcons.star,
                    accent: BisoAccent.gold,
                  ),
                  title: _durationLabel(l10n, option.primary),
                  subtitle: _planSummary(
                    context,
                    option == choice && plan != null ? plan : option.primary,
                  ),
                  trailing: Radio<String>.adaptive(value: option.duration),
                  onTap: () => pickDuration(option.duration),
                ),
            ],
          ),
        ),
      ),
      if (current != null && next != null)
        SliverToBoxAdapter(
          child: RadioGroup<bool>(
            groupValue: _startNext,
            onChanged: (value) {
              if (value != null) setState(() => _startNext = value);
            },
            child: BisoFormGroup(
              title: l10n.membershipEndsOn(
                _longDate(context, current.expiryDate),
              ),
              children: [
                BisoListRow(
                  leading: const BisoIconTile(icon: CupertinoIcons.calendar),
                  title: l10n.membershipBuyThisSemester(
                    _longDate(context, current.expiryDate),
                  ),
                  trailing: const Radio<bool>.adaptive(value: false),
                  onTap: () => setState(() => _startNext = false),
                ),
                BisoListRow(
                  leading: const BisoIconTile(
                    icon: CupertinoIcons.calendar_badge_plus,
                  ),
                  title: l10n.membershipStartNextSemester(
                    _longDate(context, next.startDate),
                    _longDate(context, next.expiryDate),
                  ),
                  trailing: const Radio<bool>.adaptive(value: true),
                  onTap: () => setState(() => _startNext = true),
                ),
              ],
            ),
          ),
        ),
      SliverToBoxAdapter(
        child: RadioGroup<String>(
          groupValue: campusId,
          onChanged: (id) {
            if (id != null) setState(() => _campusId = id);
          },
          child: BisoFormGroup(
            title: 'Your campus',
            footer: 'Your membership is booked to this campus.',
            children: [
              for (final campus in overview.campuses)
                BisoListRow(
                  leading: const BisoIconTile(
                    icon: CupertinoIcons.location_solid,
                  ),
                  title: campus.name,
                  trailing: Radio<String>.adaptive(value: campus.id),
                  onTap: () => setState(() => _campusId = campus.id),
                ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: RadioGroup<PaymentProvider>(
          groupValue: provider,
          onChanged: (value) {
            if (value != null) setState(() => _provider = value);
          },
          child: BisoFormGroup(
            title: 'How would you like to pay?',
            children: providers.when(
              loading: () => const [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (_, _) => [
                BisoListRow(
                  leading: const BisoIconTile(
                    icon: CupertinoIcons.arrow_clockwise,
                  ),
                  title: 'We could not reach the payment service',
                  subtitle: 'Tap to try again.',
                  onTap: () => ref.invalidate(paymentProvidersProvider),
                ),
              ],
              data: (options) => options.isEmpty
                  ? const [
                      BisoListRow(
                        leading: BisoIconTile(icon: CupertinoIcons.pause),
                        title: 'Payments are temporarily unavailable',
                        subtitle: 'Please try again later.',
                      ),
                    ]
                  : [
                      for (final option in options)
                        BisoListRow(
                          leading: BisoIconTile(
                            icon: option == PaymentProvider.vipps
                                ? CupertinoIcons.device_phone_portrait
                                : CupertinoIcons.creditcard,
                            accent: BisoAccent.coral,
                          ),
                          title: option.displayName,
                          subtitle: option.description,
                          trailing: Radio<PaymentProvider>.adaptive(
                            value: option,
                          ),
                          onTap: () => setState(() => _provider = option),
                        ),
                    ],
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onPay,
              icon: const Icon(CupertinoIcons.lock),
              label: Text(
                selectedPlan == null || selectedProvider == null
                    ? 'Payments unavailable'
                    : 'Pay ${formatNok(selectedPlan.price)} with '
                          '${selectedProvider.displayName}',
              ),
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Text(
            'You will be taken to your payment provider to pay, then brought '
            'back here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: palette.muted),
          ),
        ),
      ),
    ];
  }
}

/// A compact titled card with an icon, a message and an optional action.
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    this.message,
    this.accent = BisoAccent.neutral,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final BisoAccent accent;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    final body = message;
    final button = action;
    return BisoSection(
      child: BisoListGroup(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BisoIconTile(icon: icon, accent: accent),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: text.titleMedium?.copyWith(color: palette.ink),
                ),
                if (body != null && body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: text.bodyMedium?.copyWith(color: palette.muted),
                  ),
                ],
                if (button != null) ...[const SizedBox(height: 16), button],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MembershipCard extends StatelessWidget {
  const _MembershipCard({required this.overview});

  final MembershipOverview overview;

  @override
  Widget build(BuildContext context) {
    final membership = overview.currentMembership;
    final expiry = membership?.expiryDate ?? overview.currentExpiry;
    final checked = DateFormat.yMMMd().add_Hm().format(
      overview.checkedAt.toLocal(),
    );
    return BisoSection(
      title: 'Your membership',
      footer: overview.fromCache
          ? 'Last verified $checked. We could not check again just now.'
          : 'Verified with BISO $checked.',
      child: BisoListGroup(
        children: [
          BisoListRow(
            leading: const BisoIconTile(
              icon: CupertinoIcons.checkmark_seal_fill,
              accent: BisoAccent.teal,
            ),
            title: 'Active member',
            subtitle: membership?.name,
          ),
          if (expiry != null)
            BisoListRow(
              leading: const BisoIconTile(icon: CupertinoIcons.calendar),
              title: 'Valid until',
              value: _formatDate(expiry),
            ),
          if (overview.studentId != null)
            BisoListRow(
              leading: const BisoIconTile(
                icon: CupertinoIcons.person_crop_rectangle,
              ),
              title: 'Student ID',
              value: overview.studentId,
            ),
          BisoListRow(
            leading: const BisoIconTile(
              icon: CupertinoIcons.qrcode,
              accent: BisoAccent.gold,
            ),
            title: AppLocalizations.of(context)!.memberPassShowAction,
            onTap: () => context.push(memberPassPath),
          ),
        ],
      ),
    );
  }
}

class _NotMemberCard extends StatelessWidget {
  const _NotMemberCard({
    required this.overview,
    required this.email,
    required this.onLink,
    required this.onRetry,
  });

  final MembershipOverview overview;
  final String email;
  final VoidCallback onLink;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final expired = overview.lastExpiredMembership;
    final expiredNote = expired == null
        ? null
        : 'Your membership expired on ${_formatDate(expired.expiryDate)}.';
    final upcoming = overview.upcomingMembership;

    // Bought, not started: not a member yet, and nothing to claim until the
    // start date. This covers `already_member`, which with no active
    // membership means exactly this, and an eligible student who can still
    // buy a longer plan below.
    if (upcoming != null &&
        (overview.state == MembershipGateState.alreadyMember ||
            overview.state == MembershipGateState.eligible ||
            overview.state == MembershipGateState.noPlansAvailable)) {
      final start = _longDate(context, upcoming.startDate);
      final end = overview.currentExpiry ?? upcoming.expiryDate;
      return _InfoCard(
        icon: CupertinoIcons.calendar_badge_plus,
        accent: BisoAccent.teal,
        title: l10n.membershipUpcomingTitle,
        message: end == null
            ? l10n.membershipStartsOn(start)
            : l10n.membershipUpcomingDetails(start, _longDate(context, end)),
      );
    }

    return switch (overview.state) {
      MembershipGateState.needsBiLink => _InfoCard(
        icon: CupertinoIcons.link,
        accent: BisoAccent.blue,
        title: 'Link your BI student account',
        message:
            'BISO verifies memberships against your BI student record. You '
            'link your BI account once, on biso.no'
            '${email.isEmpty ? '' : ' — sign in there as $email'}.',
        action: FilledButton(
          onPressed: onLink,
          child: const Text('Link on biso.no'),
        ),
      ),
      MembershipGateState.needsDirectoryRecord => _InfoCard(
        icon: CupertinoIcons.person_crop_circle_badge_exclam,
        accent: BisoAccent.coral,
        title: "We couldn't find your BI record",
        message:
            'Your BI account is linked, but we could not read the student '
            'record BISO needs. Try again on biso.no, or contact BISO if it '
            'keeps failing.',
        action: FilledButton(
          onPressed: onLink,
          child: const Text('Try again on biso.no'),
        ),
      ),
      MembershipGateState.checkUnavailable => _InfoCard(
        icon: CupertinoIcons.exclamationmark_triangle,
        title: "We couldn't verify your membership right now",
        message: 'Pull down to refresh, or try again in a moment.',
        action: FilledButton(
          onPressed: onRetry,
          child: const Text('Try again'),
        ),
      ),
      // The website says the same thing on its own join page: nothing is on
      // sale, it is not about this student, and BISO can sort it out. The BI
      // student app does not sell BISO memberships, so it is not a way in.
      MembershipGateState.noPlansAvailable => _InfoCard(
        icon: CupertinoIcons.exclamationmark_triangle,
        accent: BisoAccent.gold,
        title: "Membership isn't on sale right now",
        message: [
          ?expiredNote,
          'We have no membership open for purchase at the moment. This is '
              'not about your account — get in touch with BISO and we will '
              'sort it out.',
        ].join(' '),
      ),
      MembershipGateState.alreadyMember ||
      MembershipGateState.eligible => _InfoCard(
        icon: CupertinoIcons.star,
        accent: BisoAccent.gold,
        title: expired == null ? 'Become a member' : 'Renew your membership',
        message: expiredNote ?? 'Join BISO for member prices and benefits.',
      ),
    };
  }
}

class _PurchaseBanner extends StatelessWidget {
  const _PurchaseBanner({
    required this.state,
    required this.onCheckAgain,
    required this.onStartOver,
    required this.onDismiss,
  });

  final MembershipPurchaseState state;
  final VoidCallback onCheckAgain;

  /// Stops waiting for a payment the student walked away from. It does not
  /// cancel the order, so the copy must not say it does.
  final VoidCallback onStartOver;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ok = TextButton(onPressed: onDismiss, child: const Text('OK'));
    return switch (state.phase) {
      MembershipPurchasePhase.idle => const SizedBox.shrink(),
      MembershipPurchasePhase.starting => const _InfoCard(
        icon: CupertinoIcons.hourglass,
        title: 'Starting payment…',
      ),
      MembershipPurchasePhase.awaitingPayment => _InfoCard(
        icon: CupertinoIcons.clock,
        accent: BisoAccent.gold,
        title: 'Waiting for your payment',
        message:
            'Finish paying in Vipps or your browser, then come back here. '
            'Changed your mind? Start over — and if that payment does go '
            'through anyway, your membership still activates.',
        action: Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: onCheckAgain,
              child: const Text('Check again'),
            ),
            TextButton(onPressed: onStartOver, child: const Text('Start over')),
          ],
        ),
      ),
      MembershipPurchasePhase.activating => const _InfoCard(
        icon: CupertinoIcons.hourglass,
        accent: BisoAccent.teal,
        title: 'Payment received — activating your membership',
      ),
      MembershipPurchasePhase.activated => _InfoCard(
        icon: CupertinoIcons.checkmark_seal_fill,
        accent: BisoAccent.teal,
        title: state.startsOn != null || state.extendsMembership
            ? l10n.membershipPurchasedTitle
            : 'Welcome to BISO!',
        message: switch (state.startsOn) {
          null => l10n.membershipActiveNow,
          final start when state.extendsMembership =>
            l10n.membershipExtendedFrom(_longDate(context, start)),
          final start => l10n.membershipPurchasedStarts(
            _longDate(context, start),
          ),
        },
        action: TextButton(onPressed: onDismiss, child: const Text('Done')),
      ),
      MembershipPurchasePhase.activationDelayed => _InfoCard(
        icon: CupertinoIcons.clock,
        accent: BisoAccent.gold,
        title: 'Payment confirmed',
        message: state.message,
        action: ok,
      ),
      MembershipPurchasePhase.cancelled => _InfoCard(
        icon: CupertinoIcons.xmark_circle,
        title: 'Payment cancelled',
        message: 'You have not been charged.',
        action: ok,
      ),
      MembershipPurchasePhase.failed => _InfoCard(
        icon: CupertinoIcons.exclamationmark_triangle,
        accent: BisoAccent.coral,
        title: 'The payment was not completed',
        message: state.message,
        action: ok,
      ),
    };
  }
}
