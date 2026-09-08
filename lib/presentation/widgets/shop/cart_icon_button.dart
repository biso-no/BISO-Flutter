import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../providers/shop/cart_provider.dart';

/// The cart entry point, with a badge for how many units are waiting.
///
/// Rendered wherever the buyer might be mid-shop, so the cart is never more
/// than one tap away and they can see at a glance that something is in it.
class CartIconButton extends ConsumerWidget {
  const CartIconButton({super.key, this.color});

  final Color? color;

  /// Past this, the badge shows "9+" rather than growing wide enough to
  /// overrun the icon.
  static const int _maxBadgeCount = 9;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(cartItemCountProvider);
    final label = count > _maxBadgeCount ? '$_maxBadgeCount+' : '$count';

    return IconButton(
      onPressed: () => context.push('/explore/products/cart'),
      tooltip: count == 0
          ? 'Your cart'
          : 'Your cart, $count ${count == 1 ? 'item' : 'items'}',
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.shopping_bag_outlined, color: color),
          if (count > 0)
            Positioned(
              right: -6,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
