import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/currency.dart';
import '../../../data/models/shop_order.dart';
import '../../../providers/shop/checkout_provider.dart';
import '../../widgets/biso/biso.dart';

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
    final palette = BisoPalette.of(context);
    final order = _order;
    final status =
        order?.status ?? ShopOrderStatus.fromValue(widget.initialStatus);

    return PopScope(
      // Back from here belongs in the shop, not on the checkout form the buyer
      // has already submitted.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/explore/products');
      },
      child: BisoPage(
        title: 'Your order',
        largeTitle: false,
        automaticallyImplyLeading: false,
        actions: [
          BisoHeaderAction(
            icon: CupertinoIcons.arrow_clockwise,
            tooltip: 'Check again',
            onPressed: _isVerifying ? null : _verify,
          ),
        ],
        onRefresh: _verify,
        slivers: [
          SliverToBoxAdapter(
            child: BisoSection(
              child: _StatusHeader(
                status: status,
                isVerifying: _isVerifying && order == null,
              ),
            ),
          ),
          if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.muted,
                  ),
                ),
              ),
            ),
          if (order != null)
            SliverToBoxAdapter(child: _OrderSummary(order: order)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Column(children: _buildActions(status, order)),
            ),
          ),
        ],
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
            icon: const Icon(CupertinoIcons.arrow_up_right_square),
            label: const Text('Continue payment'),
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
            icon: const Icon(CupertinoIcons.doc_text),
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
            icon: const Icon(CupertinoIcons.cart),
            label: const Text('Back to cart'),
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
    final palette = BisoPalette.of(context);
    final (icon, color, title, message) = _presentation(palette);

    return Column(
      children: [
        if (isVerifying)
          const SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(),
          )
        else
          // Not a BisoIconTile: its colors are the fixed category accents,
          // while this glyph must track the status token itself.
          DecoratedBox(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: SizedBox.square(
              dimension: 56,
              child: Icon(icon, size: 32, color: color),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(color: palette.ink),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: palette.muted),
        ),
      ],
    );
  }

  /// Maps every [ShopOrderStatus] onto the three status glyphs/tokens: `paid`
  /// and `authorized` both mean the money is in, so they share the success
  /// checkmark; `pending` is the only waiting state, so it takes the warning
  /// clock; `cancelled`, `failed` and `refunded` all mean there is no longer
  /// a live paid order, so they share the error xmark.
  (IconData, Color, String, String) _presentation(BisoPalette palette) {
    switch (status) {
      case ShopOrderStatus.paid:
      case ShopOrderStatus.authorized:
        return (
          CupertinoIcons.checkmark_circle_fill,
          palette.success,
          'Payment complete',
          'Thank you! Your order is confirmed and BISO has been notified.',
        );
      case ShopOrderStatus.cancelled:
        return (
          CupertinoIcons.xmark_circle_fill,
          palette.error,
          'Payment cancelled',
          'Nothing has been charged. Your cart is still here if you want to '
              'try again.',
        );
      case ShopOrderStatus.failed:
        return (
          CupertinoIcons.xmark_circle_fill,
          palette.error,
          'Payment failed',
          'Your payment did not go through, and nothing has been charged.',
        );
      case ShopOrderStatus.refunded:
        return (
          CupertinoIcons.xmark_circle_fill,
          palette.error,
          'Order refunded',
          'This order has been refunded.',
        );
      case ShopOrderStatus.pending:
        return (
          CupertinoIcons.clock,
          palette.warning,
          'Waiting for your payment',
          'Finish the payment in your payment app. This page updates by '
              'itself once it goes through.',
        );
    }
  }
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({required this.order});

  final ShopOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);

    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      color: palette.ink,
    );
    final subtitleStyle = theme.textTheme.bodyMedium?.copyWith(
      color: palette.muted,
    );
    final amountStyle = theme.textTheme.bodyLarge?.copyWith(
      color: palette.muted,
    );
    final discountStyle = theme.textTheme.titleMedium?.copyWith(
      color: palette.success,
    );
    final discountAmountStyle = theme.textTheme.bodyLarge?.copyWith(
      color: palette.success,
    );

    final rows = <Widget>[
      for (final item in order.items)
        _AmountRow(
          title: item.name,
          subtitle: _itemSubtitle(item),
          amount: formatNok(item.lineTotal),
          titleStyle: titleStyle,
          subtitleStyle: subtitleStyle,
          amountStyle: amountStyle,
        ),
    ];

    if (order.discountTotal > 0) {
      rows.add(
        _AmountRow(
          title: 'Member discount',
          amount: '-${formatNok(order.discountTotal)}',
          titleStyle: discountStyle,
          amountStyle: discountAmountStyle,
        ),
      );
    }

    rows.add(
      _AmountRow(
        title: 'Total',
        amount: formatNok(order.total),
        titleStyle: titleStyle,
        amountStyle: theme.textTheme.headlineMedium?.copyWith(
          color: palette.ink,
        ),
      ),
    );

    return BisoFormGroup(title: 'Order ${order.id}', children: rows);
  }

  /// Quantity and unit price on the first line, followed by one line per
  /// custom-field answer the buyer gave at checkout — every one of them,
  /// since these are the exact details (size, name for engraving, …) the
  /// order was placed for.
  String _itemSubtitle(ShopOrderItem item) {
    final lines = ['${item.quantity} × ${formatNok(item.unitPrice)}'];
    for (final answer in item.customFields) {
      lines.add('${answer.label}: ${answer.value}');
    }
    return lines.join('\n');
  }
}

/// One "label — amount" row (a line total, Member discount, or Total), sized
/// so the amount is never scaled down, and never silently clipped, at any
/// text scale (R11). Copied from `_AmountRow` in `checkout_screen.dart` (see
/// its doc comment for the full layout rationale) with one change: the
/// subtitle here can carry several lines — quantity/price plus one line per
/// custom-field answer — and every one of them must stay readable, so this
/// copy does not cap it at 2 lines the way checkout's per-line subtitle
/// (a single quantity/price line, never more) does.
class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.title,
    this.subtitle,
    required this.amount,
    this.titleStyle,
    this.subtitleStyle,
    this.amountStyle,
  });

  final String title;
  final String? subtitle;
  final String amount;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final TextStyle? amountStyle;

  static const _spacing = 8.0;
  static const _minLabelFraction = 0.4;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 10),
        child: MergeSemantics(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth;
              final painter = TextPainter(
                text: TextSpan(text: amount, style: amountStyle),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 1,
              )..layout();
              final sideBySide =
                  maxWidth.isFinite &&
                  (maxWidth - painter.width - _spacing) >=
                      maxWidth * _minLabelFraction;
              final fitsOneLine =
                  sideBySide || !maxWidth.isFinite || painter.width <= maxWidth;

              final amountText = fitsOneLine
                  ? Text(
                      amount,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      softWrap: false,
                      style: amountStyle,
                    )
                  : Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      children: [
                        for (final piece in amount.split(' '))
                          Text(
                            piece,
                            maxLines: 1,
                            softWrap: false,
                            style: amountStyle,
                          ),
                      ],
                    );

              final label = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: sideBySide ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!, style: subtitleStyle),
                    ),
                ],
              );

              if (sideBySide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: label),
                    const SizedBox(width: _spacing),
                    amountText,
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  label,
                  const SizedBox(height: 4),
                  Align(alignment: Alignment.centerRight, child: amountText),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
