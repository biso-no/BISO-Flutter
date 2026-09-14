import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/biso_glass.dart';
import '../../../core/theme/premium_theme.dart';
import 'premium_components.dart';

/// Premium Layout Components
///
/// Sophisticated layout widgets that create beautiful, hierarchical
/// designs with proper spacing, shadows, and visual flow.

// === PREMIUM SCAFFOLD ===

class PremiumScaffold extends StatelessWidget {
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigation;
  final Widget? floatingActionButton;
  final Color? backgroundColor;
  final bool extendBodyBehindAppBar;
  final bool hasGradientBackground;
  final List<Color>? gradientColors;

  const PremiumScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigation,
    this.floatingActionButton,
    this.backgroundColor,
    this.extendBodyBehindAppBar = false,
    this.hasGradientBackground = false,
    this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultBgColor = isDark ? AppColors.charcoalBlack : AppColors.pearl;

    return Scaffold(
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      backgroundColor: Colors.transparent,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      body: Container(
        decoration: BoxDecoration(
          color: hasGradientBackground
              ? null
              : (backgroundColor ?? defaultBgColor),
          gradient: hasGradientBackground
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors:
                      gradientColors ??
                      [
                        isDark ? AppColors.charcoalBlack : AppColors.pearl,
                        isDark ? AppColors.smokeGray : Colors.white,
                      ],
                )
              : null,
        ),
        child: body,
      ),
      bottomNavigationBar: bottomNavigation,
    );
  }
}

// === PREMIUM SECTION ===

class PremiumSection extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final String? actionText;
  final VoidCallback? onActionTap;
  final IconData? icon;
  final bool hasBackground;
  final Color? backgroundColor;

  const PremiumSection({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
    this.padding,
    this.margin,
    this.actionText,
    this.onActionTap,
    this.icon,
    this.hasBackground = false,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: margin ?? const EdgeInsets.symmetric(vertical: 8),
      padding: hasBackground
          ? (padding ?? const EdgeInsets.all(20))
          : EdgeInsets.zero,
      decoration: hasBackground
          ? BoxDecoration(
              color:
                  backgroundColor ??
                  (isDark ? AppColors.smokeGray : Colors.white),
              borderRadius: BorderRadius.circular(20),
              boxShadow: PremiumTheme.softShadow,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            PremiumSectionHeader(
              title: title!,
              subtitle: subtitle,
              actionText: actionText,
              onActionTap: onActionTap,
              icon: icon,
            ),

          if (!hasBackground)
            Padding(
              padding: padding ?? const EdgeInsets.symmetric(horizontal: 20),
              child: child,
            )
          else
            child,
        ],
      ),
    );
  }
}

// === PREMIUM GRID ===

class PremiumGrid extends StatelessWidget {
  final List<Widget> children;
  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double childAspectRatio;
  final EdgeInsets? padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  const PremiumGrid({
    super.key,
    required this.children,
    this.crossAxisCount = 2,
    this.mainAxisSpacing = 16,
    this.crossAxisSpacing = 16,
    this.childAspectRatio = 1.0,
    this.padding,
    this.shrinkWrap = false,
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
      childAspectRatio: childAspectRatio,
      padding: padding ?? const EdgeInsets.all(20),
      shrinkWrap: shrinkWrap,
      physics: physics,
      children: children,
    );
  }
}

// === PREMIUM CONTAINER ===

class PremiumContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Color? color;
  final List<Color>? gradientColors;
  final double borderRadius;
  final bool hasGlow;
  final bool isGlass;
  final List<BoxShadow>? customShadow;
  final Border? border;
  final double? width;
  final double? height;

  const PremiumContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.gradientColors,
    this.borderRadius = 20,
    this.hasGlow = false,
    this.isGlass = false,
    this.customShadow,
    this.border,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultColor = isDark ? AppColors.smokeGray : Colors.white;

    if (isGlass) {
      return BisoGlassContainer(
        width: width,
        height: height,
        margin: margin,
        padding: padding ?? const EdgeInsets.all(20),
        borderRadius: borderRadius,

        child: gradientColors == null
            ? child
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradientColors!,
                  ),
                ),
                child: child,
              ),
      );
    }

    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: gradientColors == null ? (color ?? defaultColor) : null,
        gradient: gradientColors != null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors!,
              )
            : null,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border,
        boxShadow:
            customShadow ??
            (hasGlow
                ? [
                    BoxShadow(
                      color: (color ?? AppColors.biLightBlue).withValues(
                        alpha: 0.2,
                      ),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                    ...PremiumTheme.mediumShadow,
                  ]
                : PremiumTheme.softShadow),
      ),
      child: child,
    );
  }
}

