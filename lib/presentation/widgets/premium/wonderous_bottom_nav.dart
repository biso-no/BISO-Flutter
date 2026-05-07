import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class WonderousBottomNavBar extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;
  final List<WonderousNavItem> items;

  const WonderousBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  State<WonderousBottomNavBar> createState() => _WonderousBottomNavBarState();
}

class _WonderousBottomNavBarState extends State<WonderousBottomNavBar>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _rippleController;
  late Animation<double> _animation;
  late Animation<double> _rippleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _rippleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutCubic,
    );
    _rippleAnimation = CurvedAnimation(
      parent: _rippleController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(WonderousBottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _animationController.forward(from: 0);
      _rippleController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowMedium,
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 40,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Animated indicator background
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              final itemWidth =
                  MediaQuery.of(context).size.width / widget.items.length;
              final indicatorLeft = itemWidth * widget.currentIndex;

              return Positioned(
                left: indicatorLeft + itemWidth * 0.15,
                top: 12,
                child: Container(
                  width: itemWidth * 0.7,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: AppColors.eventGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.crystalBlue.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Ripple effect
          AnimatedBuilder(
            animation: _rippleAnimation,
            builder: (context, child) {
              final itemWidth =
                  MediaQuery.of(context).size.width / widget.items.length;
              final rippleLeft =
                  itemWidth * widget.currentIndex + itemWidth * 0.5;

              return Positioned(
                left: rippleLeft - 30,
                top: 30,
                child: Container(
                  width: 60 * _rippleAnimation.value,
                  height: 60 * _rippleAnimation.value,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.crystalBlue.withValues(
                      alpha: (1 - _rippleAnimation.value) * 0.2,
                    ),
                  ),
                ),
              );
            },
          ),

          // Navigation items
          Positioned.fill(
            child: Row(
              children: widget.items.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                final isSelected = index == widget.currentIndex;

                return Expanded(
                  child: _WonderousNavButton(
                    item: item,
                    isSelected: isSelected,
                    onTap: () => widget.onTap(index),
                    animation: _animation,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _WonderousNavButton extends StatefulWidget {
  final WonderousNavItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final Animation<double> animation;

  const _WonderousNavButton({
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.animation,
  });

  @override
  State<_WonderousNavButton> createState() => _WonderousNavButtonState();
}

class _WonderousNavButtonState extends State<_WonderousNavButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _bounceAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _bounceController.forward(),
      onTapUp: (_) => _bounceController.reverse(),
      onTapCancel: () => _bounceController.reverse(),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _bounceAnimation,
        builder: (context, child) => Transform.scale(
          scale: _bounceAnimation.value,
          child: SizedBox(
            height: 90,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon with animation
                AnimatedBuilder(
                  animation: widget.animation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: widget.isSelected
                          ? 1.0 + (widget.animation.value * 0.1)
                          : 1.0,
                      child: Icon(
                        widget.isSelected
                            ? widget.item.activeIcon
                            : widget.item.icon,
                        size: 24,
                        color: widget.isSelected
                            ? AppColors.white
                            : AppColors.stoneGray,
                      ),
                    );
                  },
                ),

                const SizedBox(height: 4),

                // Label with premium styling
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: widget.isSelected
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: widget.isSelected
                        ? AppColors.white
                        : AppColors.stoneGray,
                    fontFamily: 'Inter',
                  ),
                  child: Text(
                    widget.item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WonderousNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const WonderousNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

// Premium floating action button for special actions (like AI copilot)
class WonderousFloatingAction extends StatefulWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final List<Color>? gradientColors;

  const WonderousFloatingAction({
    super.key,
    this.onPressed,
    required this.icon,
    this.gradientColors,
  });

  @override
  State<WonderousFloatingAction> createState() =>
      _WonderousFloatingActionState();
}

class _WonderousFloatingActionState extends State<WonderousFloatingAction>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 0.1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      onTap: widget.onPressed,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: Transform.rotate(
            angle: _rotationAnimation.value,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: widget.gradientColors ?? AppColors.eventGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (widget.gradientColors ?? AppColors.eventGradient)
                        .first
                        .withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: AppColors.shadowMedium,
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(widget.icon, color: AppColors.white, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}
