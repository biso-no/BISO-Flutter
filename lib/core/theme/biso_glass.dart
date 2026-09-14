import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Compatibility names for the existing screens. Content is deliberately
/// opaque Flutter material; only BisoChrome creates native glass surfaces.
class BisoGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double? width;
  final double? height;
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
    this.useOwnLayer = false,
    this.clipBehavior = Clip.antiAlias,
  });
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding ?? EdgeInsets.zero,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: AppColors.biNavy.withValues(alpha: 0.025),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: clipBehavior,
      child: Material(type: MaterialType.transparency, child: child),
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
    this.useOwnLayer = false,
  });
  @override
  Widget build(BuildContext context) => BisoGlassCard(
    padding: padding,
    margin: margin,
    borderRadius: borderRadius,
    width: width,
    height: height,
    child: alignment == null
        ? child
        : Align(alignment: alignment!, child: child),
  );
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
  Widget build(BuildContext context) => AppBar(
    title: title,
    leading: leading,
    actions: actions,
    centerTitle: centerTitle,
    foregroundColor: foregroundColor,
    toolbarHeight: height,
    backgroundColor: Theme.of(context).colorScheme.surface,
  );
}
