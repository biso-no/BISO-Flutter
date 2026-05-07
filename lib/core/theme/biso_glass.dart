import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../constants/app_colors.dart';

class BisoGlass {
  static const qualityPreferenceKey = 'biso_glass_quality';

  static GlassQuality? parseQuality(String? value) {
    if (value == null) return null;
    for (final quality in GlassQuality.values) {
      if (quality.name == value) return quality;
    }
    return null;
  }

  static const theme = GlassThemeData(
    light: GlassThemeVariant(
      settings: GlassThemeSettings(
        thickness: 28,
        blur: 10,
        glassColor: Color(0x40E6F2FA),
        chromaticAberration: 0.24,
        refractiveIndex: 1.28,
        lightIntensity: 1.15,
        ambientStrength: 0.28,
        saturation: 1.08,
        specularSharpness: GlassSpecularSharpness.medium,
      ),
      quality: GlassQuality.standard,
      glowColors: GlassGlowColors(
        primary: AppColors.biLightBlue,
        secondary: AppColors.biNavy,
        success: AppColors.green9,
        warning: AppColors.orange9,
        danger: AppColors.error,
        info: AppColors.biLightBlue,
        glowBlurRadius: 12,
        glowSpreadRadius: 0.12,
        glowOpacity: 0.55,
      ),
      borderRadius: 18,
    ),
    dark: GlassThemeVariant(
      settings: GlassThemeSettings(
        thickness: 42,
        blur: 14,
        glassColor: Color(0x3001417B),
        chromaticAberration: 0.28,
        refractiveIndex: 1.3,
        lightIntensity: 1.3,
        ambientStrength: 0.22,
        saturation: 1.12,
        specularSharpness: GlassSpecularSharpness.medium,
      ),
      quality: GlassQuality.standard,
      glowColors: GlassGlowColors(
        primary: AppColors.biLightBlue,
        secondary: AppColors.skyBlue,
        success: AppColors.green9,
        warning: AppColors.orange9,
        danger: AppColors.error,
        info: AppColors.biLightBlue,
        glowBlurRadius: 14,
        glowSpreadRadius: 0.10,
        glowOpacity: 0.45,
      ),
      borderRadius: 18,
    ),
  );

  static const fixedSurfaceSettings = LiquidGlassSettings(
    thickness: 38,
    blur: 12,
    glassColor: Color(0x36E6F2FA),
    chromaticAberration: 0.3,
    refractiveIndex: 1.32,
    lightIntensity: 1.25,
    ambientStrength: 0.24,
    saturation: 1.1,
    specularSharpness: GlassSpecularSharpness.medium,
  );

  static const cardSettings = LiquidGlassSettings(
    thickness: 22,
    blur: 8,
    glassColor: Color(0x55FFFFFF),
    chromaticAberration: 0.12,
    refractiveIndex: 1.18,
    lightIntensity: 0.95,
    ambientStrength: 0.36,
    saturation: 1.02,
    specularSharpness: GlassSpecularSharpness.soft,
  );

  static const denseSettings = LiquidGlassSettings(
    thickness: 20,
    blur: 8,
    glassColor: Color(0x44FFFFFF),
    lightIntensity: 0.82,
    ambientStrength: 0.42,
    saturation: 1.03,
    specularSharpness: GlassSpecularSharpness.soft,
  );
}

class BisoGlassScope extends StatelessWidget {
  final Widget child;

  const BisoGlassScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GlassBackdropScope(child: child);
  }
}

class BisoGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double? width;
  final double? height;
  final GlassQuality quality;
  final bool useOwnLayer;
  final Clip clipBehavior;

  const BisoGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.borderRadius = 18,
    this.width,
    this.height,
    this.quality = GlassQuality.standard,
    this.useOwnLayer = false,
    this.clipBehavior = Clip.antiAlias,
  });

  @override
  Widget build(BuildContext context) {
    if (quality == GlassQuality.minimal) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Container(
        width: width,
        height: height,
        margin: margin,
        padding: padding ?? EdgeInsets.zero,
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.surfaceDark.withValues(alpha: 0.94)
              : Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: isDark
                ? AppColors.outlineDark.withValues(alpha: 0.55)
                : AppColors.outlineVariant,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.06),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: clipBehavior,
        child: child,
      );
    }

    return GlassCard(
      width: width,
      height: height,
      margin: margin,
      padding: padding ?? EdgeInsets.zero,
      shape: LiquidRoundedSuperellipse(borderRadius: borderRadius),
      settings: quality == GlassQuality.minimal
          ? BisoGlass.denseSettings
          : BisoGlass.cardSettings,
      quality: quality,
      useOwnLayer: useOwnLayer,
      clipBehavior: clipBehavior,
      child: child,
    );
  }
}

class BisoGlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double? width;
  final double? height;
  final AlignmentGeometry? alignment;
  final GlassQuality quality;
  final bool useOwnLayer;

  const BisoGlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 18,
    this.width,
    this.height,
    this.alignment,
    this.quality = GlassQuality.standard,
    this.useOwnLayer = false,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      alignment: alignment,
      shape: LiquidRoundedSuperellipse(borderRadius: borderRadius),
      settings: quality == GlassQuality.minimal
          ? BisoGlass.denseSettings
          : BisoGlass.cardSettings,
      quality: quality,
      useOwnLayer: useOwnLayer,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class BisoGlassNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Color? glowColor;

  const BisoGlassNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.glowColor,
  });
}

class BisoGlassBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<BisoGlassNavItem> items;

  const BisoGlassBottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedColor = isDark ? AppColors.skyBlue : AppColors.biNavy;
    final unselectedColor = isDark
        ? Colors.white.withValues(alpha: 0.62)
        : AppColors.stoneGray;

    return AdaptiveLiquidGlassLayer(
      settings: BisoGlass.fixedSurfaceSettings,
      quality: GlassQuality.standard,
      blendAmount: 10,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: GlassBottomBar(
          selectedIndex: currentIndex,
          onTabSelected: onTap,
          tabs: [
            for (final item in items)
              GlassBottomBarTab(
                label: item.label,
                icon: Icon(item.icon),
                activeIcon: Icon(item.activeIcon),
                glowColor: item.glowColor ?? AppColors.biLightBlue,
              ),
          ],
          selectedIconColor: selectedColor,
          unselectedIconColor: unselectedColor,
          indicatorColor: AppColors.biLightBlue.withValues(alpha: 0.22),
          interactionGlowColor: AppColors.biLightBlue,
          quality: GlassQuality.standard,
          glassSettings: BisoGlass.fixedSurfaceSettings,
          barHeight: 62,
          verticalPadding: 10,
          horizontalPadding: 8,
          tabWidth: null,
          iconSize: 23,
          labelFontSize: 11,
          textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class BisoGlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool centerTitle;
  final Color? foregroundColor;
  final double height;

  const BisoGlassAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.centerTitle = false,
    this.foregroundColor,
    this.height = kToolbarHeight,
  });

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color =
        foregroundColor ?? (isDark ? AppColors.pearl : AppColors.strongBlue);

    return GlassAppBar(
      title: title == null
          ? null
          : DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
              child: title!,
            ),
      leading: leading,
      actions: actions,
      centerTitle: centerTitle,
      preferredSize: Size.fromHeight(height),
      settings: BisoGlass.fixedSurfaceSettings,
      quality: GlassQuality.standard,
      useOwnLayer: true,
    );
  }
}
