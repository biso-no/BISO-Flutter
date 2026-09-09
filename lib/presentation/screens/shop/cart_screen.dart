import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/cart_item.dart';
import '../../../providers/shop/cart_provider.dart';

/// The cart: what the buyer has picked, before they commit to paying.
///
/// Prices here are the app's own indicative figures. The real amount — with the
/// member discount resolved — is fetched from the server on the checkout
/// screen, so nothing on this screen is ever presented as the final total.
class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cart = ref.watch(cartProvider);

    // A reservation sync can discover that stock went while the buyer was
    // deciding. Say so once, then forget it.
    ref.listen<String?>(cartProvider.select((state) => state.error), (
      previous,
      next,
    ) {
      if (next == null || next == previous) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next)));
      ref.read(cartProvider.notifier).clearError();
    });

    return Scaffold(
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        elevation: 0,
        leading: NavigationUtils.buildBackButton(
          context,
          fallbackRoute: '/explore/products',
        ),
        title: const Text('Your cart'),
        centerTitle: true,
        actions: [
          if (!cart.isEmpty)
            TextButton(
              onPressed: _confirmClear,
              child: const Text('Clear'),
            ),
        ],
      ),
      body: _buildBody(cart, theme),
      bottomNavigationBar: cart.isEmpty
          ? null
          : _CartSummaryBar(
              subtotal: cart.subtotal,
              itemCount: cart.itemCount,
              onCheckout: () => context.push('/explore/products/checkout'),
            ),
    );
  }

  Widget _buildBody(CartState cart, ThemeData theme) {
    if (cart.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (cart.isEmpty) {
      return _EmptyCart(onBrowse: () => context.go('/explore/products'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: cart.items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = cart.items[index];
        return _CartLine(
          item: item,
          onQuantityChanged: (quantity) => ref
              .read(cartProvider.notifier)
              .setQuantity(item.lineId, quantity),
          onRemove: () => ref.read(cartProvider.notifier).removeLine(item.lineId),
        );
      },
    );
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Empty your cart?'),
        content: const Text('This removes everything you have added.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Empty cart'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(cartProvider.notifier).clear();
    }
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart({required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.shopping_bag_outlined,
              size: 64,
              color: AppColors.mist,
            ),
            const SizedBox(height: 16),
            Text(
              'Your cart is empty',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Merch, tickets and everything else BISO sells lives in the shop.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onBrowse,
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Browse the shop'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.defaultBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartLine extends StatelessWidget {
  const _CartLine({
    required this.item,
    required this.onQuantityChanged,
    required this.onRemove,
  });

  final CartItem item;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The stepper stops at the stock the product had when it was added; the
    // server clamps for real, this just avoids obviously futile taps.
    final canIncrease = item.stock == null || item.quantity < item.stock!;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.subtleBlue.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gray100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 72,
              height: 72,
              child: item.imageUrl == null
                  ? Container(
                      color: AppColors.gray100,
                      child: const Icon(
                        Icons.image_outlined,
                        color: AppColors.charcoalBlack,
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: item.imageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Container(
                        color: AppColors.gray100,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.charcoalBlack,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (item.variationName != null &&
                    item.variationName!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.variationName!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
                // The buyer's answers are part of what makes this line
                // distinct from another line of the same product, so they
                // belong on the line rather than hidden until the receipt.
                for (final entry in item.customFields.entries)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${item.customFieldLabels[entry.key] ?? entry.key}: '
                      '${entry.value}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _QuantityStepper(
                      quantity: item.quantity,
                      canIncrease: canIncrease,
                      onChanged: onQuantityChanged,
                    ),
                    const Spacer(),
                    Text(
                      formatNok(item.lineTotal),
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
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 20),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.canIncrease,
    required this.onChanged,
  });

  final int quantity;
  final bool canIncrease;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gray100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () => onChanged(quantity - 1),
            icon: const Icon(Icons.remove_rounded, size: 18),
            tooltip: 'Decrease quantity',
          ),
          Text(
            '$quantity',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: canIncrease ? () => onChanged(quantity + 1) : null,
            icon: const Icon(Icons.add_rounded, size: 18),
            tooltip: 'Increase quantity',
          ),
        ],
      ),
    );
  }
}

class _CartSummaryBar extends StatelessWidget {
  const _CartSummaryBar({
    required this.subtotal,
    required this.itemCount,
    required this.onCheckout,
  });

  final double subtotal;
  final int itemCount;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  formatNok(subtotal),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Member discounts are applied at checkout',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onCheckout,
                icon: const Icon(Icons.lock_outline_rounded),
                label: const Text('Go to checkout'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: AppColors.defaultBlue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
