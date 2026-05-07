import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
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
  final PremiumAppBar? appBar;
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

// === PREMIUM APP BAR ===

class PremiumAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final bool centerTitle;
  final bool isTransparent;
  final bool hasBlur;
  final Color? backgroundColor;
  final VoidCallback? onBackPressed;
  final double elevation;

  const PremiumAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.centerTitle = false,
    this.isTransparent = false,
    this.hasBlur = false,
    this.backgroundColor,
    this.onBackPressed,
    this.elevation = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final statusBarHeight = MediaQuery.of(context).padding.top;

    final bgColor =
        backgroundColor ??
        (isTransparent
            ? Colors.transparent
            : (isDark ? AppColors.charcoalBlack : Colors.white));

    if (hasBlur) {
      return BisoGlassAppBar(
        title:
            titleWidget ??
            (title != null
                ? Text(
                    title!,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.pearl : AppColors.charcoalBlack,
                    ),
                  )
                : null),
        centerTitle: centerTitle,
        leading:
            leading ??
            (Navigator.of(context).canPop()
                ? PremiumIconButton(
                    icon: Icons.arrow_back_ios,
                    onPressed:
                        onBackPressed ?? () => Navigator.of(context).pop(),
                    isGlass: true,
                  )
                : null),
        actions: actions,
      );
    }

    Widget appBarContent = Container(
      height: kToolbarHeight + statusBarHeight,
      padding: EdgeInsets.only(top: statusBarHeight, left: 4, right: 4),
      decoration: BoxDecoration(
        color: hasBlur ? bgColor.withValues(alpha: 0.8) : bgColor,
        boxShadow: elevation > 0
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: elevation * 2,
                  offset: Offset(0, elevation),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          // Leading
          if (leading != null)
            leading!
          else if (Navigator.of(context).canPop())
            PremiumIconButton(
              icon: Icons.arrow_back_ios,
              onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
            ),

          // Title
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: centerTitle
                    ? Alignment.center
                    : Alignment.centerLeft,
                child:
                    titleWidget ??
                    (title != null
                        ? Text(
                            title!,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppColors.pearl
                                  : AppColors.charcoalBlack,
                            ),
                          )
                        : const SizedBox.shrink()),
              ),
            ),
          ),

          // Actions
          if (actions != null)
            Row(mainAxisSize: MainAxisSize.min, children: actions!),
        ],
      ),
    );

    return appBarContent;
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

// === PREMIUM ICON BUTTON ===

class PremiumIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? iconColor;
  final Color? backgroundColor;
  final double size;
  final bool isGlass;
  final String? tooltip;

  const PremiumIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.iconColor,
    this.backgroundColor,
    this.size = 44,
    this.isGlass = false,
    this.tooltip,
  });

  @override
  State<PremiumIconButton> createState() => _PremiumIconButtonState();
}

class _PremiumIconButtonState extends State<PremiumIconButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: PremiumTheme.fastAnimation,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: PremiumTheme.premiumCurve),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor =
        widget.iconColor ?? (isDark ? AppColors.mist : AppColors.stoneGray);

    if (widget.isGlass) {
      Widget button = GlassIconButton(
        icon: Icon(widget.icon, color: iconColor, size: widget.size * 0.45),
        onPressed: widget.onPressed,
        size: widget.size,
        shape: GlassIconButtonShape.circle,
        settings: BisoGlass.fixedSurfaceSettings,
        quality: GlassQuality.standard,
        glowColor: AppColors.accentBlue,
      );

      if (widget.tooltip != null) {
        button = Tooltip(message: widget.tooltip!, child: button);
      }

      return button;
    }

    Widget button = GestureDetector(
      onTapDown: widget.onPressed != null ? (_) => _controller.forward() : null,
      onTapUp: widget.onPressed != null ? (_) => _controller.reverse() : null,
      onTapCancel: () => _controller.reverse(),
      onTap: widget.onPressed,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: widget.isGlass
                ? PremiumTheme.glassContainer(
                    borderRadius: BorderRadius.circular(widget.size / 2),
                  )
                : BoxDecoration(
                    color:
                        widget.backgroundColor ??
                        (isDark ? AppColors.smokeGray : AppColors.cloud),
                    borderRadius: BorderRadius.circular(widget.size / 2),
                    boxShadow: PremiumTheme.softShadow,
                  ),
            child: Icon(
              widget.icon,
              size: widget.size * 0.45,
              color: iconColor,
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }

    return button;
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

// === PREMIUM LIST ===

class PremiumList extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets? padding;
  final double spacing;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final Axis scrollDirection;

  const PremiumList({
    super.key,
    required this.children,
    this.padding,
    this.spacing = 12,
    this.shrinkWrap = false,
    this.physics,
    this.scrollDirection = Axis.vertical,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: scrollDirection,
      padding: padding ?? const EdgeInsets.all(20),
      shrinkWrap: shrinkWrap,
      physics: physics,
      itemCount: children.length,
      separatorBuilder: (_, _) => scrollDirection == Axis.vertical
          ? SizedBox(height: spacing)
          : SizedBox(width: spacing),
      itemBuilder: (context, index) => children[index],
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
        quality: GlassQuality.standard,
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

// === PREMIUM HERO SECTION ===

class PremiumHero extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? child;
  final List<Color>? gradientColors;
  final String? backgroundImage;
  final double height;
  final Widget? overlay;
  final CrossAxisAlignment alignment;

  const PremiumHero({
    super.key,
    required this.title,
    this.subtitle,
    this.child,
    this.gradientColors,
    this.backgroundImage,
    this.height = 300,
    this.overlay,
    this.alignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors ?? [AppColors.biLightBlue, AppColors.biNavy],
        ),
        image: backgroundImage != null
            ? DecorationImage(
                image: AssetImage(backgroundImage!),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.3),
                  BlendMode.darken,
                ),
              )
            : null,
      ),
      child: Stack(
        children: [
          // Main content
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: alignment,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: alignment == CrossAxisAlignment.center
                      ? TextAlign.center
                      : TextAlign.left,
                ),

                if (subtitle != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    subtitle!,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      height: 1.4,
                    ),
                    textAlign: alignment == CrossAxisAlignment.center
                        ? TextAlign.center
                        : TextAlign.left,
                  ),
                ],

                if (child != null) ...[const SizedBox(height: 24), child!],
              ],
            ),
          ),

          // Overlay content
          if (overlay != null) Positioned.fill(child: overlay!),
        ],
      ),
    );
  }
}
