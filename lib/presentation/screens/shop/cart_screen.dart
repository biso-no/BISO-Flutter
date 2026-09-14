import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/currency.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/cart_item.dart';
import '../../../providers/shop/cart_provider.dart';
import '../../widgets/biso/biso.dart';

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

    final leading = BisoBackButton(
      onPressed: () => NavigationUtils.safeGoBack(
        context,
        fallbackRoute: '/explore/products',
      ),
    );

    if (cart.isLoading) {
      return BisoPage(
        title: 'Your cart',
        largeTitle: false,
        leading: leading,
        slivers: const [SliverToBoxAdapter(child: BisoSkeleton.rows())],
      );
    }

    if (cart.isEmpty) {
      return BisoPage(
        title: 'Your cart',
        leading: leading,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoEmptyState(
              icon: CupertinoIcons.bag,
              accent: BisoAccent.gold,
              title: 'Your cart is empty',
              message:
                  'Merch, tickets and everything else BISO sells lives in '
                  'the shop.',
              action: FilledButton.icon(
                onPressed: () => context.go('/explore/products'),
                icon: const Icon(CupertinoIcons.bag),
                label: const Text('Browse the shop'),
              ),
            ),
          ),
        ],
      );
    }

    return BisoPage(
      title: 'Your cart',
      leading: leading,
      actions: [
        BisoHeaderAction(
          icon: CupertinoIcons.trash,
          tooltip: 'Clear',
          onPressed: _confirmClear,
        ),
      ],
      slivers: [
        SliverBisoListGroup(
          dividerIndent: 16,
          itemCount: cart.items.length,
          itemBuilder: (context, index) {
            final item = cart.items[index];
            return _CartLine(
              key: ValueKey('cart-line-${item.lineId}'),
              item: item,
              onQuantityChanged: (quantity) => ref
                  .read(cartProvider.notifier)
                  .setQuantity(item.lineId, quantity),
            );
          },
        ),
      ],
      bottomBar: BisoBottomBar(
        child: _CartSummary(
          subtotal: cart.subtotal,
          itemCount: cart.itemCount,
          onCheckout: () => context.push('/explore/products/checkout'),
        ),
      ),
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

class _CartLine extends StatelessWidget {
  const _CartLine({super.key, required this.item, required this.onQuantityChanged});

  final CartItem item;
  final ValueChanged<int> onQuantityChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    // The stepper stops at the stock the product had when it was added; the
    // server clamps for real, this just avoids obviously futile taps.
    final canIncrease = item.stock == null || item.quantity < item.stock!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 56,
              height: 56,
              child: item.imageUrl == null
                  ? ColoredBox(
                      color: palette.surfaceRaised,
                      child: Icon(CupertinoIcons.photo, color: palette.muted),
                    )
                  : CachedNetworkImage(
                      imageUrl: item.imageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => ColoredBox(
                        color: palette.surfaceRaised,
                        child: Icon(
                          CupertinoIcons.exclamationmark_triangle,
                          color: palette.muted,
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
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: palette.ink,
                  ),
                ),
                if (item.variationName != null &&
                    item.variationName!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      item.variationName!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.muted,
                      ),
                    ),
                  ),
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
                        color: palette.muted,
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
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        formatNok(item.lineTotal),
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: palette.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
    final palette = BisoPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 44,
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: () => onChanged(quantity - 1),
              icon: Icon(CupertinoIcons.minus, size: 16, color: palette.ink),
              tooltip: 'Decrease quantity',
            ),
          ),
          SizedBox(
            width: 24,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: palette.ink),
            ),
          ),
          SizedBox.square(
            dimension: 44,
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: canIncrease ? () => onChanged(quantity + 1) : null,
              icon: Icon(
                CupertinoIcons.plus,
                size: 16,
                color: canIncrease ? palette.ink : palette.muted,
              ),
              tooltip: 'Increase quantity',
            ),
          ),
        ],
      ),
    );
  }
}

class _CartSummary extends StatelessWidget {
  const _CartSummary({
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
    final palette = BisoPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.muted,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatNok(subtotal),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: palette.ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            'Member discounts are applied at checkout',
            style: theme.textTheme.bodySmall?.copyWith(color: palette.muted),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onCheckout,
            icon: const Icon(CupertinoIcons.lock),
            label: const Text('Go to checkout'),
          ),
        ),
      ],
    );
  }
}
