import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/biso_glass.dart';
import '../../../core/theme/premium_theme.dart';

/// Premium Navigation System
///
/// A sophisticated floating navigation bar that creates an exclusive,
/// iOS-inspired experience with glass morphism and elegant animations.

class PremiumBottomNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<PremiumNavItem> items;
  final bool floating;

  const PremiumBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.floating = true,
  });

  @override
  State<PremiumBottomNav> createState() => _PremiumBottomNavState();
}

class _PremiumBottomNavState extends State<PremiumBottomNav> {
  @override
  Widget build(BuildContext context) {
    if (widget.floating) {
      return _buildFloatingNav();
    } else {
      return _buildStandardNav();
    }
  }

  Widget _buildFloatingNav() {
    return Positioned(
      bottom: 0,
      left: 8,
      right: 8,
      child: BisoGlassBottomNavigation(
        currentIndex: widget.currentIndex,
        onTap: widget.onTap,
        items: [
          for (final item in widget.items)
            BisoGlassNavItem(
              icon: item.icon,
              activeIcon: item.activeIcon,
              label: item.label,
              glowColor: AppColors.biLightBlue,
            ),
        ],
      ),
    );
  }

  Widget _buildStandardNav() {
    return BisoGlassBottomNavigation(
      currentIndex: widget.currentIndex,
      onTap: widget.onTap,
      items: [
        for (final item in widget.items)
          BisoGlassNavItem(
            icon: item.icon,
            activeIcon: item.activeIcon,
            label: item.label,
            glowColor: AppColors.biLightBlue,
          ),
      ],
    );
  }
}

// === PREMIUM BADGE ===

class PremiumBadge extends StatelessWidget {
  final String? text;
  final bool showDot;
  final Color? color;

  const PremiumBadge({super.key, this.text, this.showDot = false, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badgeColor = color ?? AppColors.error;

    if (showDot && (text == null || text!.isEmpty)) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: badgeColor,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: badgeColor.withValues(alpha: 0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: badgeColor.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text ?? '',
        style: theme.textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// === PREMIUM NAV ITEM ===

class PremiumNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Widget? badge;

  const PremiumNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badge,
  });
}

// === PREMIUM TAB VIEW ===

class PremiumTabView extends StatefulWidget {
  final List<PremiumTab> tabs;
  final int initialIndex;
  final ValueChanged<int>? onChanged;
  final bool isScrollable;

  const PremiumTabView({
    super.key,
    required this.tabs,
    this.initialIndex = 0,
    this.onChanged,
    this.isScrollable = false,
  });

  @override
  State<PremiumTabView> createState() => _PremiumTabViewState();
}

class _PremiumTabViewState extends State<PremiumTabView>
    with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.tabs.length,
      initialIndex: widget.initialIndex,
      vsync: this,
    );
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        widget.onChanged?.call(_tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? AppColors.smokeGray : AppColors.cloud,
            borderRadius: BorderRadius.circular(16),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: widget.isScrollable,
            indicator: BoxDecoration(
              color: isDark ? AppColors.stoneGray : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: PremiumTheme.softShadow,
            ),
            indicatorPadding: const EdgeInsets.all(4),
            labelColor: isDark ? AppColors.pearl : AppColors.charcoalBlack,
            unselectedLabelColor: isDark ? AppColors.mist : AppColors.stoneGray,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
            dividerColor: Colors.transparent,
            overlayColor: WidgetStateProperty.all(Colors.transparent),
            tabs: widget.tabs
                .map(
                  (tab) => Tab(
                    text: tab.title,
                    icon: tab.icon != null ? Icon(tab.icon, size: 20) : null,
                  ),
                )
                .toList(),
          ),
        ),

        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: widget.tabs.map((tab) => tab.content).toList(),
          ),
        ),
      ],
    );
  }
}

class PremiumTab {
  final String title;
  final IconData? icon;
  final Widget content;

  const PremiumTab({required this.title, this.icon, required this.content});
}
