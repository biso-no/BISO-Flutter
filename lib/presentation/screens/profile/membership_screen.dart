import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/currency.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/membership_overview.dart';
import '../../../data/models/payment_provider.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/membership/membership_checkout_provider.dart';
import '../../../providers/membership/membership_overview_provider.dart';
import '../../../providers/shop/checkout_provider.dart';
import '../../widgets/biso/biso.dart';

/// Where a student links their BI account. BI's tenant is reachable only
/// through Appwrite's OIDC provider, in a browser holding the student's own
/// biso.no session, so the app hands this step to the website.
final membershipLinkUrl = Uri.parse('https://biso.no/membership/link');

String _formatDate(DateTime? date) =>
    date == null ? '' : DateFormat.yMMMd().format(date);

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
  String? _planId;
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
    final plans = overview.offeredPlans;
    final plan =
        plans.where((option) => option.id == _planId).firstOrNull ??
        plans.firstOrNull;
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

    return [
      SliverToBoxAdapter(
        child: RadioGroup<String>(
          groupValue: plan?.id,
          onChanged: (id) {
            if (id != null) setState(() => _planId = id);
          },
          child: BisoFormGroup(
            title: overview.isMember
                ? 'Extend your membership'
                : 'Choose a membership',
            children: [
              for (final option in plans)
                BisoListRow(
                  leading: const BisoIconTile(
                    icon: CupertinoIcons.star,
                    accent: BisoAccent.gold,
                  ),
                  title: option.name,
                  subtitle:
                      '${formatNok(option.price)} · valid until '
                      '${_formatDate(option.expiryDate)}',
                  trailing: Radio<String>.adaptive(value: option.id),
                  onTap: () => setState(() => _planId = option.id),
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
    final expired = overview.lastExpiredMembership;
    final expiredNote = expired == null
        ? null
        : 'Your membership expired on ${_formatDate(expired.expiryDate)}.';

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
      MembershipGateState.noPlansAvailable => _InfoCard(
        icon: CupertinoIcons.star,
        accent: BisoAccent.gold,
        title: "You're not a member",
        message: [
          ?expiredNote,
          'No memberships are on sale in the app right now. You can still '
              'join through the BI student app.',
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
    required this.onDismiss,
  });

  final MembershipPurchaseState state;
  final VoidCallback onCheckAgain;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
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
        message: 'Finish paying in Vipps or your browser, then come back here.',
        action: TextButton(
          onPressed: onCheckAgain,
          child: const Text('Check again'),
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
        title: 'Welcome to BISO!',
        message: 'Your membership is active.',
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
