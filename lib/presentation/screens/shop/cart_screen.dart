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
              onRemove: () =>
                  ref.read(cartProvider.notifier).removeLine(item.lineId),
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
  const _CartLine({
    super.key,
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
    final palette = BisoPalette.of(context);
    // The stepper stops at the stock the product had when it was added; the
    // server clamps for real, this just avoids obviously futile taps.
    final canIncrease = item.stock == null || item.quantity < item.stock!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                          child: Icon(
                            CupertinoIcons.photo,
                            color: palette.muted,
                          ),
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
                    // distinct from another line of the same product, so
                    // they belong on the line rather than hidden until the
                    // receipt.
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
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: onRemove,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(CupertinoIcons.xmark, size: 18, color: palette.muted),
                tooltip: 'Remove',
              ),
            ],
          ),
          const SizedBox(height: 8),
          // The stepper and the price each get a full-width line of their
          // own: sharing one row left too little space for a wide price
          // ("NOK 1234.50") beside a two-digit quantity at large text
          // scales (R11 — amounts and counts never truncate).
          _QuantityStepper(
            quantity: item.quantity,
            canIncrease: canIncrease,
            onChanged: onQuantityChanged,
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              formatNok(item.lineTotal),
              maxLines: 1,
              style: theme.textTheme.titleMedium?.copyWith(color: palette.ink),
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
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 24),
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
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

/// The bar's subtotal, sized so it is never truncated, scaled down, or
/// broken mid-number (R11): it measures its own natural single-line width
/// and, if the bar isn't wide enough for that (a large cart's total at a
/// large text scale, in `headlineMedium` — the biggest style either screen
/// uses), splits on `formatNok`'s one space into the currency code and the
/// number, as two single-line `Text`s in a `Wrap`. That only ever breaks
/// *between* the code and the number, never inside either one — unlike a
/// plain, uncapped `Text`, which would happily hard-wrap in the middle of
/// the digits once nothing softer is left to break on.
///
/// Like `_AmountRow` on checkout, the whole amount sits under one
/// [MergeSemantics], so a screen reader announces the split pieces as one
/// amount rather than "NOK" and the number as two separate elements.
class _SubtotalAmount extends StatelessWidget {
  const _SubtotalAmount({required this.subtotal});

  final double subtotal;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final style = Theme.of(
      context,
    ).textTheme.headlineMedium?.copyWith(color: palette.ink);
    final amount = formatNok(subtotal);

    return MergeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final painter = TextPainter(
            text: TextSpan(text: amount, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final fitsOneLine = !maxWidth.isFinite || painter.width <= maxWidth;

          if (fitsOneLine) {
            return Text(amount, maxLines: 1, softWrap: false, style: style);
          }
          return Wrap(
            alignment: WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              for (final piece in amount.split(' '))
                Text(piece, maxLines: 1, softWrap: false, style: style),
            ],
          );
        },
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // An `Expanded` count next to a fixed/`Flexible` subtotal splits the
        // bar's width between them, so at large text scales either the
        // count ellipsizes or (a big enough cart) the subtotal has to
        // shrink to fit — R11 says neither may happen. Stacking gives each
        // its own full-width line instead, at natural, unscaled size.
        Text(
          '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
          maxLines: 1,
          style: theme.textTheme.bodyMedium?.copyWith(color: palette.muted),
        ),
        const SizedBox(height: 2),
        _SubtotalAmount(subtotal: subtotal),
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
