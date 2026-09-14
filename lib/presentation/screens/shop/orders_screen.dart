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
        largeTitle: false,
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
        largeTitle: false,
        leading: leading,
        slivers: const [SliverToBoxAdapter(child: BisoSkeleton.rows())],
      ),
      error: (_, _) => BisoPage(
        title: 'Your orders',
        largeTitle: false,
        leading: leading,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    final (label, color) = _statusPresentation(order.status, palette);
    final date = order.createdAt;
    final itemCount = order.itemCount;
    final itemsLabel = '$itemCount ${itemCount == 1 ? 'item' : 'items'}';

    return BisoListRow(
      leading: const BisoIconTile(icon: CupertinoIcons.bag, accent: BisoAccent.gold),
      title: 'Order ${order.id}',
      subtitle: date != null
          ? '${DateFormat.yMMMd().format(date)} • $itemsLabel'
          : itemsLabel,
      onTap: () => context.push('/explore/products/order/${order.id}'),
      trailing: _OrderAmountAndStatus(
        amount: formatNok(order.total),
        amountStyle: theme.textTheme.titleSmall?.copyWith(color: palette.ink),
        statusLabel: label,
        statusColor: color,
      ),
    );
  }
}

/// The total, above its status pill, right-aligned.
///
/// `BisoListRow`'s `Row` lays out `trailing` with unbounded width — the same
/// reason `value:` needs its own `Flexible` — so a trailing child that simply
/// reports its own natural size can make the *whole row* overflow instead of
/// letting the (already shrinkable) title give way. Declaring a fixed
/// [_width] here gives the row a bounded, predictable footprint no matter how
/// wide the amount or the status label want to be, while [amount] itself
/// still never truncates or scales down (R11): it renders on one line if it
/// fits [_width], or — the same last resort `_AmountRow` in
/// `checkout_screen.dart`/`order_screen.dart` uses — splits only on the
/// single space `formatNok` always produces, between the currency code and
/// the number, never inside either. The status label isn't an amount, so it
/// simply wraps onto a second line if [_width] is not enough for it.
class _OrderAmountAndStatus extends StatelessWidget {
  const _OrderAmountAndStatus({
    required this.amount,
    required this.amountStyle,
    required this.statusLabel,
    required this.statusColor,
  });

  final String amount;
  final TextStyle? amountStyle;
  final String statusLabel;
  final Color statusColor;

  static const _width = 170.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
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

/// Maps every [ShopOrderStatus] onto the three tokens the pill can show:
/// `paid` and `authorized` both mean the money is in, so they share
/// [BisoPalette.success]; `pending` is the only waiting state, so it takes
/// [BisoPalette.warning]; `cancelled`, `failed` and `refunded` all mean there
/// is no longer a live paid order, so they share [BisoPalette.error].
(String, Color) _statusPresentation(ShopOrderStatus status, BisoPalette palette) {
  return switch (status) {
    ShopOrderStatus.paid ||
    ShopOrderStatus.authorized => ('Paid', palette.success),
    ShopOrderStatus.pending => ('Awaiting payment', palette.warning),
    ShopOrderStatus.cancelled => ('Cancelled', palette.error),
    ShopOrderStatus.failed => ('Failed', palette.error),
    ShopOrderStatus.refunded => ('Refunded', palette.error),
  };
}
