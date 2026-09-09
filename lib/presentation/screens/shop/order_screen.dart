import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency.dart';
import '../../../data/models/shop_order.dart';
import '../../../providers/shop/checkout_provider.dart';

/// Where the buyer waits for, and then sees the result of, a payment.
///
/// This screen is opened *before* the buyer leaves for Vipps or the card form,
/// so there is always somewhere to come back to — whether they finish, cancel,
/// or simply switch away. Three things bring it up to date, in order of how
/// fast they are and how much they can be relied on:
///
/// 1. the deep link from the return route, which carries the resolved status;
/// 2. coming back to the foreground, which is what happens when a browser
///    declines to hand the custom scheme back to the app;
/// 3. a poll while the order is still pending, for the case where the buyer
///    completes payment on another device and never returns here at all.
///
/// None of them is load-bearing for the money: the provider webhook and the
/// reconciliation cron settle the order regardless of what the app does.
class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({super.key, required this.orderId, this.initialStatus});

  final String orderId;

  /// The status the return route already resolved, when the app was opened by
  /// its deep link. Only used to pick the first frame — the verification call
  /// below is what the screen actually trusts.
  final String? initialStatus;

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  /// A payment can take a moment to settle after the buyer confirms it, so a
  /// pending order is re-checked a handful of times before the screen stops
  /// asking and leaves it to the buyer to refresh.
  static const Duration _pollInterval = Duration(seconds: 4);
  static const int _maxPolls = 15;

  late final AppLifecycleListener _lifecycle;
  Timer? _pollTimer;
  int _polls = 0;

  ShopOrder? _order;
  bool _isVerifying = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _handleResume);
    unawaited(_verify());
  }

  @override
  void didUpdateWidget(covariant OrderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The deep link can land on this route while it is already open (the buyer
    // returns from the provider). Re-verify rather than showing stale state.
    if (oldWidget.orderId != widget.orderId ||
        oldWidget.initialStatus != widget.initialStatus) {
      _polls = 0;
      unawaited(_verify());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _handleResume() {
    if (!mounted) return;
    if (_order?.status.isSuccessful == true) return;
    _polls = 0;
    unawaited(_verify());
  }

  Future<void> _verify() async {
    if (!mounted) return;
    setState(() {
      _isVerifying = true;
      _error = null;
    });

    try {
      final order = await ref
          .read(checkoutControllerProvider.notifier)
          .verifyOrder(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
        _isVerifying = false;
      });
      _scheduleNextPoll(order);
    } catch (error) {
      if (!mounted) return;
      // Fall back to the stored row so the buyer still sees their order rather
      // than an error page, even if the provider check could not be made.
      final snapshot = await ref.read(
        orderSnapshotProvider(widget.orderId).future,
      );
      if (!mounted) return;
      setState(() {
        _order = snapshot;
        _isVerifying = false;
        _error = snapshot == null
            ? 'We could not load this order.'
            : 'We could not reach the payment provider just now.';
      });
      _scheduleNextPoll(snapshot);
    }
  }

  void _scheduleNextPoll(ShopOrder? order) {
    _pollTimer?.cancel();
    if (order == null || !order.status.isPending) return;
    if (_polls >= _maxPolls) return;
    _polls++;
    _pollTimer = Timer(_pollInterval, () {
      if (mounted) unawaited(_verify());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final order = _order;
    final status =
        order?.status ??
        ShopOrderStatus.fromValue(widget.initialStatus);

    return PopScope(
      // Back from here belongs in the shop, not on the checkout form the buyer
      // has already submitted.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/explore/products');
      },
      child: Scaffold(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        appBar: AppBar(
          backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Text('Your order'),
          centerTitle: true,
          actions: [
            IconButton(
              onPressed: _isVerifying ? null : _verify,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Check again',
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _verify,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _StatusHeader(
                status: status,
                isVerifying: _isVerifying && order == null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
              if (order != null) ...[
                const SizedBox(height: 24),
                _OrderDetails(order: order),
              ],
              const SizedBox(height: 24),
              ..._buildActions(status, order),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions(ShopOrderStatus status, ShopOrder? order) {
    final actions = <Widget>[];

    if (status.isPending && order?.paymentLink != null) {
      actions.add(
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(order!.paymentLink!),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Continue payment'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppColors.defaultBlue,
            ),
          ),
        ),
      );
      actions.add(const SizedBox(height: 12));
    }

    if (status.isSuccessful && order?.receiptUrl != null) {
      actions.add(
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(order!.receiptUrl!),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('View receipt'),
          ),
        ),
      );
      actions.add(const SizedBox(height: 12));
    }

    if (status.isFailure) {
      actions.add(
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => context.go('/explore/products/cart'),
            icon: const Icon(Icons.shopping_cart_outlined),
            label: const Text('Back to cart'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppColors.defaultBlue,
            ),
          ),
        ),
      );
      actions.add(const SizedBox(height: 12));
    }

    actions.add(
      SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: () => context.go('/explore/products'),
          child: const Text('Back to the shop'),
        ),
      ),
    );
    return actions;
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.status, required this.isVerifying});

  final ShopOrderStatus status;
  final bool isVerifying;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, title, message) = _presentation();

    return Column(
      children: [
        if (isVerifying)
          const SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(),
          )
        else
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
            ),
            child: Icon(icon, size: 36, color: color),
          ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  (IconData, Color, String, String) _presentation() {
    switch (status) {
      case ShopOrderStatus.paid:
      case ShopOrderStatus.authorized:
        return (
          Icons.check_circle_rounded,
          AppColors.success,
          'Payment complete',
          'Thank you! Your order is confirmed and BISO has been notified.',
        );
      case ShopOrderStatus.cancelled:
        return (
          Icons.cancel_outlined,
          AppColors.onSurfaceVariant,
          'Payment cancelled',
          'Nothing has been charged. Your cart is still here if you want to '
              'try again.',
        );
      case ShopOrderStatus.failed:
        return (
          Icons.error_outline_rounded,
          AppColors.error,
          'Payment failed',
          'Your payment did not go through, and nothing has been charged.',
        );
      case ShopOrderStatus.refunded:
        return (
          Icons.replay_rounded,
          AppColors.onSurfaceVariant,
          'Order refunded',
          'This order has been refunded.',
        );
      case ShopOrderStatus.pending:
        return (
          Icons.hourglass_top_rounded,
          AppColors.defaultBlue,
          'Waiting for your payment',
          'Finish the payment in your payment app. This page updates by '
              'itself once it goes through.',
        );
    }
  }
}

class _OrderDetails extends StatelessWidget {
  const _OrderDetails({required this.order});

  final ShopOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order ${order.id}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final item in order.items) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${item.quantity} × ${formatNok(item.unitPrice)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      for (final answer in item.customFields)
                        Text(
                          '${answer.label}: ${answer.value}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(formatNok(item.lineTotal)),
              ],
            ),
            const SizedBox(height: 12),
          ],
          const Divider(),
          if (order.discountTotal > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Text(
                    'Member discount',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.success,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '-${formatNok(order.discountTotal)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Text(
                'Total',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                formatNok(order.total),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.defaultBlue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
