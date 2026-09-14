import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/currency.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/shop_order.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/shop/checkout_provider.dart';
import '../../widgets/biso/biso.dart';

/// Everything the buyer has bought from the BISO shop.
///
/// Reads the `orders` rows directly: each carries a read grant for the buyer
/// who placed it, so the signed-in user's own client returns exactly their
/// orders. Only opening one goes through the API, to re-check it with the
/// payment provider.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuthenticated = ref.watch(authStateProvider).isAuthenticated;
    final leading = BisoBackButton(
      onPressed: () =>
          NavigationUtils.safeGoBack(context, fallbackRoute: '/profile'),
    );

    if (!isAuthenticated) {
      return BisoPage(
        title: 'Your orders',
        leading: leading,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoEmptyState(
              icon: CupertinoIcons.lock,
              accent: BisoAccent.gold,
              title: 'Sign in to see your orders',
              message: 'Your purchases are tied to your BISO account.',
            ),
          ),
        ],
      );
    }

    return _OrdersList(leading: leading);
  }
}

class _OrdersList extends ConsumerWidget {
  const _OrdersList({required this.leading});

  final Widget leading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(myOrdersProvider);

    return orders.when(
      loading: () => BisoPage(
        title: 'Your orders',
        leading: leading,
        slivers: const [SliverToBoxAdapter(child: BisoSkeleton.rows())],
      ),
      error: (_, _) => BisoPage(
        title: 'Your orders',
        leading: leading,
        onRefresh: () async => ref.invalidate(myOrdersProvider),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoEmptyState(
              icon: CupertinoIcons.exclamationmark_triangle,
              title: 'We could not load your orders',
              message: 'Pull down to try again.',
              action: FilledButton(
                onPressed: () => ref.invalidate(myOrdersProvider),
                child: const Text('Try again'),
              ),
            ),
          ),
        ],
      ),
      data: (data) => BisoPage(
        title: 'Your orders',
        leading: leading,
        onRefresh: () async => ref.invalidate(myOrdersProvider),
        slivers: data.isEmpty
            ? [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: BisoEmptyState(
                    icon: CupertinoIcons.bag,
                    accent: BisoAccent.gold,
                    title: 'No orders yet',
                    message:
                        'Anything you buy in the BISO shop shows up here.',
                  ),
                ),
              ]
            : [
                SliverBisoListGroup(
                  itemCount: data.length,
                  itemBuilder: (context, index) =>
                      _OrderRow(order: data[index]),
                ),
              ],
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});

  final ShopOrder order;

  /// Everything the trailing block (`Row`'s non-flex `trailing` slot, or the
  /// stacked footer line) is reserved space for, besides itself: the
  /// [SliverBisoListGroup] margin (16pt each side), `BisoListRow`'s own
  /// padding (16pt each side), the leading icon tile (32pt) and its gap
  /// (12pt), and the gap before `trailing` (8pt). 32+32+32+12+8 = 116.
  static const _rowOverhead = 116.0;

  /// What's reserved for a stacked footer line: just the list-group margin
  /// and its own matching horizontal padding (no leading icon or gaps, since
  /// it isn't inside `BisoListRow`'s own `Row`). 16+16+16+16 = 64.
  static const _footerOverhead = 64.0;

  static const _pillPadding = 20.0; // 10pt each side, matches the Container.

  void _navigate(BuildContext context) =>
      context.push('/explore/products/order/${order.id}');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    final (label, color) = _statusPresentation(order.status, palette);
    final date = order.createdAt;
    final itemNames = order.items
        .map((item) => item.name.trim())
        .where((name) => name.isNotEmpty)
        .join(', ');
    final itemCount = order.itemCount;
    final itemsPart = itemNames.isNotEmpty
        ? itemNames
        : '$itemCount ${itemCount == 1 ? 'item' : 'items'}';
    final subtitle = date != null
        ? '${DateFormat.yMMMd().format(date)} • $itemsPart'
        : itemsPart;

    final amount = formatNok(order.total);
    final amountStyle = theme.textTheme.titleSmall?.copyWith(color: palette.ink);
    final pillStyle = theme.textTheme.labelSmall?.copyWith(color: color);

    // Measured, not guessed (fix round 1): a fixed trailing width either
    // wastes space or starves the title — real order ids run to ~20
    // characters, and a fixed box sized for the amount/pill leaves as little
    // as 34pt for the title+subtitle on a 320pt phone. Sizing the block to
    // what its own content actually needs, capped by the row's real width,
    // gives the title back that space whenever the amount/pill don't need
    // it.
    final direction = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    double measure(String text, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      return painter.width;
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final rowWidth = (screenWidth - _rowOverhead).clamp(0.0, double.infinity);
    final contentWidth = [
      measure(amount, amountStyle),
      measure(label, pillStyle) + _pillPadding,
    ].reduce((a, b) => a > b ? a : b);
    final trailingWidth = contentWidth < rowWidth ? contentWidth : rowWidth;

    // Side by side only if the title would still keep a real share of the
    // row (about 40%, mirroring `_AmountRow`'s own threshold) — otherwise an
    // id-length title would be squeezed down to almost nothing beside a
    // trailing block sized for the amount/pill.
    final sideBySide =
        rowWidth > 0 && (rowWidth - trailingWidth) >= rowWidth * 0.4;

    final leading = const BisoIconTile(
      icon: CupertinoIcons.bag,
      accent: BisoAccent.gold,
    );

    final title = 'Order ${order.id}';

    if (sideBySide) {
      return BisoListRow(
        leading: leading,
        title: title,
        subtitle: subtitle,
        onTap: () => _navigate(context),
        trailing: _OrderAmountAndStatus(
          amount: amount,
          amountStyle: amountStyle,
          statusLabel: label,
          statusColor: color,
          width: trailingWidth,
        ),
      );
    }

    // Not enough room beside the title: put the amount and pill on their own
    // right-aligned line under the subtitle instead — the same stacked idea
    // `_AmountRow` falls back to when a label and its amount don't fit one
    // line together. This isn't `BisoListRow` (whose title/subtitle cap at
    // 2 lines each, tuned for its normal — trailing-present — width): a real
    // order id can run to ~20 characters, and stacking already means the
    // title/subtitle have the row to themselves, so they're given more
    // room to wrap into rather than ellipsizing.
    final footerWidth = (screenWidth - _footerOverhead).clamp(
      0.0,
      double.infinity,
    );
    return MergeSemantics(
      child: InkWell(
        onTap: () => _navigate(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  leading,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: palette.ink,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: palette.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _OrderAmountAndStatus(
                  amount: amount,
                  amountStyle: amountStyle,
                  statusLabel: label,
                  statusColor: color,
                  width: footerWidth,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The total, above its status pill, right-aligned, sized to [width].
///
/// `BisoListRow`'s `Row` lays out a non-flex `trailing` child with unbounded
/// width — the same reason `value:` needs its own `Flexible` — so a trailing
/// child that simply reports its own natural size can make the *whole row*
/// overflow instead of letting the (shrinkable) title give way. [_OrderRow]
/// measures [amount] and [statusLabel] itself and passes the resulting
/// [width] in (content-sized, not a guess), so this widget only needs to
/// honor it. [amount] still never truncates or scales down (R11): it renders
/// on one line if it fits [width], or — the same last resort `_AmountRow` in
/// `checkout_screen.dart`/`order_screen.dart` uses — splits only on the
/// single space `formatNok` always produces, between the currency code and
/// the number, never inside either. The status label isn't an amount, so it
/// simply wraps onto a second line if [width] is not enough for it.
class _OrderAmountAndStatus extends StatelessWidget {
  const _OrderAmountAndStatus({
    required this.amount,
    required this.amountStyle,
    required this.statusLabel,
    required this.statusColor,
    required this.width,
  });

  final String amount;
  final TextStyle? amountStyle;
  final String statusLabel;
  final Color statusColor;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final painter = TextPainter(
                text: TextSpan(text: amount, style: amountStyle),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 1,
              )..layout();
              if (painter.width <= constraints.maxWidth) {
                return Text(
                  amount,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  softWrap: false,
                  style: amountStyle,
                );
              }
              return Wrap(
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
            },
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              statusLabel,
              textAlign: TextAlign.end,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: statusColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps every [ShopOrderStatus] onto the pill's token (fix round 1, ruling
/// B): `paid` and `authorized` both mean the money is in, so they share
/// [BisoPalette.success]; `pending` is the only waiting state, so it takes
/// [BisoPalette.warning]; `cancelled` and `failed` both mean nothing was (or
/// stays) charged, so they share [BisoPalette.error]; `refunded` is neither —
/// money moved and then moved back — so it gets its own, calmer
/// [BisoPalette.muted] rather than borrowing the error token.
(String, Color) _statusPresentation(ShopOrderStatus status, BisoPalette palette) {
  return switch (status) {
    ShopOrderStatus.paid ||
    ShopOrderStatus.authorized => ('Paid', palette.success),
    ShopOrderStatus.pending => ('Awaiting payment', palette.warning),
    ShopOrderStatus.cancelled => ('Cancelled', palette.error),
    ShopOrderStatus.failed => ('Failed', palette.error),
    ShopOrderStatus.refunded => ('Refunded', palette.muted),
  };
}
