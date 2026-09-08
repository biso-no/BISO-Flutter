import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/shop_order.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/shop/checkout_provider.dart';

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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isAuthenticated = ref.watch(authStateProvider).isAuthenticated;

    return Scaffold(
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        elevation: 0,
        leading: NavigationUtils.buildBackButton(
          context,
          fallbackRoute: '/profile',
        ),
        title: const Text('Your orders'),
        centerTitle: true,
      ),
      body: isAuthenticated
          ? _OrdersList()
          : _EmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Sign in to see your orders',
              message: 'Your purchases are tied to your BISO account.',
            ),
    );
  }
}

class _OrdersList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(myOrdersProvider);

    return orders.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'We could not load your orders',
        message: 'Pull down to try again.',
        onRetry: () => ref.invalidate(myOrdersProvider),
      ),
      data: (data) {
        if (data.isEmpty) {
          return _EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No orders yet',
            message: 'Anything you buy in the BISO shop shows up here.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(myOrdersProvider),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: data.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _OrderCard(order: data[index]),
          ),
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final ShopOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = _statusPresentation(order.status);
    final date = order.createdAt;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/explore/products/order/${order.id}'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gray100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                if (date != null)
                  Text(
                    DateFormat.yMMMd().format(date),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              order.items.isEmpty
                  ? 'Order ${order.id}'
                  : order.items.map((item) => item.name).join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${order.itemCount} '
                  '${order.itemCount == 1 ? 'item' : 'items'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  formatNok(order.total),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.defaultBlue,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  (String, Color) _statusPresentation(ShopOrderStatus status) {
    return switch (status) {
      ShopOrderStatus.paid ||
      ShopOrderStatus.authorized => ('Paid', AppColors.success),
      ShopOrderStatus.pending => ('Awaiting payment', AppColors.defaultBlue),
      ShopOrderStatus.cancelled => ('Cancelled', AppColors.onSurfaceVariant),
      ShopOrderStatus.failed => ('Failed', AppColors.error),
      ShopOrderStatus.refunded => ('Refunded', AppColors.onSurfaceVariant),
    };
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.mist),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
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
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
