import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/biso_glass.dart';
import '../../../core/theme/premium_theme.dart';

/// Premium UI Components Collection
///
/// A comprehensive set of luxury UI components designed to replace
/// Material Design elements with sophisticated, exclusive alternatives.

// === PREMIUM BUTTON SYSTEM ===

class PremiumButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isSecondary;
  final IconData? icon;
  final Color? customColor;
  final Color? customTextColor;
  final EdgeInsets? padding;
  final double? width;
  final double borderRadius;
  const PremiumButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isSecondary = false,
    this.icon,
    this.customColor,
    this.customTextColor,
    this.padding,
    this.width,
    this.borderRadius = 24,
  });
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground =
        customTextColor ?? (isSecondary ? scheme.primary : scheme.onPrimary);
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(44, 48)),
      padding: WidgetStatePropertyAll(
        padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? scheme.onSurface.withValues(alpha: 0.38)
            : foreground,
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => isSecondary
            ? Colors.transparent
            : states.contains(WidgetState.disabled)
            ? scheme.onSurface.withValues(alpha: 0.12)
            : customColor ?? scheme.primary,
      ),
    );
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
          ),
          const SizedBox(width: 10),
        ] else if (icon != null) ...[
          Icon(icon, size: 19),
          const SizedBox(width: 8),
        ],
        Flexible(child: Text(text, textAlign: TextAlign.center)),
      ],
    );
    return SizedBox(
      width: width,
      child: isSecondary
          ? OutlinedButton(
              onPressed: isLoading ? null : onPressed,
              style: style,
              child: content,
            )
          : FilledButton(
              onPressed: isLoading ? null : onPressed,
              style: style,
              child: content,
            ),
    );
  }
}

// === PREMIUM CARD SYSTEM ===

class PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final bool hasGlow;
  final bool isGlass;
  final List<Color>? gradientColors;
  final double borderRadius;

  const PremiumCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.backgroundColor,
    this.hasGlow = false,
    this.isGlass = false,
    this.gradientColors,
    this.borderRadius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget card = isGlass
        ? BisoGlassCard(
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
          )
        : Container(
            margin: margin,
            padding: padding ?? const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color:
                  backgroundColor ??
                  (isDark ? AppColors.smokeGray : Colors.white),
              borderRadius: BorderRadius.circular(borderRadius),
              gradient: gradientColors != null
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradientColors!,
                    )
                  : null,
              boxShadow: hasGlow
                  ? [
                      BoxShadow(
                        color: (backgroundColor ?? AppColors.biLightBlue)
                            .withValues(alpha: 0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                      ...PremiumTheme.mediumShadow,
                    ]
                  : PremiumTheme.softShadow,
            ),
            child: child,
          );

    if (onTap != null) {
      return PremiumInkWell(
        onTap: onTap!,
        borderRadius: BorderRadius.circular(borderRadius),
        child: card,
      );
    }

    return card;
  }
}

// === PREMIUM INKWELL (CUSTOM RIPPLE) ===

class PremiumInkWell extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final BorderRadius? borderRadius;
  final Color? splashColor;

  const PremiumInkWell({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius,
    this.splashColor,
  });

  @override
  State<PremiumInkWell> createState() => _PremiumInkWellState();
}

class _PremiumInkWellState extends State<PremiumInkWell>
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
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
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
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) =>
            Transform.scale(scale: _scaleAnimation.value, child: widget.child),
      ),
    );
  }
}

// === PREMIUM INPUT FIELD ===

class PremiumTextField extends StatefulWidget {
  final String? label;
  final String? hint;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixTap;
  final TextInputType? keyboardType;
  final String? errorText;
  final bool isGlass;
  final int? maxLines;

  const PremiumTextField({
    super.key,
    this.label,
    this.hint,
    this.initialValue,
    this.onChanged,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixTap,
    this.keyboardType,
    this.errorText,
    this.isGlass = false,
    this.maxLines = 1,
  });

  @override
  State<PremiumTextField> createState() => _PremiumTextFieldState();
}

class _PremiumTextFieldState extends State<PremiumTextField>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Color?> _borderColorAnimation;
  final FocusNode _focusNode = FocusNode();
  late TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: PremiumTheme.mediumAnimation,
      vsync: this,
    );
    _borderColorAnimation =
        ColorTween(begin: AppColors.cloud, end: AppColors.biLightBlue).animate(
          CurvedAnimation(
            parent: _controller,
            curve: PremiumTheme.premiumCurve,
          ),
        );

    _textController = TextEditingController(text: widget.initialValue);
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              widget.label!,
              style: theme.textTheme.labelLarge?.copyWith(
                color: isDark ? AppColors.mist : AppColors.stoneGray,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],

        AnimatedBuilder(
          animation: _borderColorAnimation,
          builder: (context, child) {
            final field = TextField(
              controller: _textController,
              focusNode: _focusNode,
              onChanged: widget.onChanged,
              obscureText: widget.obscureText,
              keyboardType: widget.keyboardType,
              maxLines: widget.maxLines,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: isDark ? AppColors.pearl : AppColors.charcoalBlack,
              ),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: theme.textTheme.bodyLarge?.copyWith(
                  color: isDark ? AppColors.stoneGray : AppColors.mist,
                ),
                prefixIcon: widget.prefixIcon != null
                    ? Icon(
                        widget.prefixIcon,
                        color: isDark ? AppColors.mist : AppColors.stoneGray,
                      )
                    : null,
                suffixIcon: widget.suffixIcon != null
                    ? GestureDetector(
                        onTap: widget.onSuffixTap,
                        child: Icon(
                          widget.suffixIcon,
                          color: isDark ? AppColors.mist : AppColors.stoneGray,
                        ),
                      )
                    : null,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
              ),
            );

            if (widget.isGlass) {
              return BisoGlassContainer(
                padding: EdgeInsets.zero,
                borderRadius: 16,

                child: field,
              );
            }

            return Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.smokeGray : AppColors.pearl,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: widget.errorText != null
                      ? AppColors.error
                      : (_borderColorAnimation.value ?? AppColors.cloud),
                  width: _focusNode.hasFocus ? 2 : 1,
                ),
                boxShadow: _focusNode.hasFocus
                    ? [
                        BoxShadow(
                          color: AppColors.biLightBlue.withValues(alpha: 0.1),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: field,
            );
          },
        ),

        if (widget.errorText != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              widget.errorText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// === PREMIUM CHIP ===

class PremiumChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? selectedColor;
  final bool isGlass;

  const PremiumChip({
    super.key,
    required this.label,
    this.isSelected = false,
    this.onTap,
    this.icon,
    this.selectedColor,
    this.isGlass = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = isSelected
        ? (selectedColor ?? AppColors.biLightBlue)
        : (isDark ? AppColors.smokeGray : AppColors.cloud);
    final textColor = isSelected
        ? Colors.white
        : (isDark ? AppColors.mist : AppColors.stoneGray);

    return PremiumInkWell(
      onTap: onTap ?? () {},
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? null
              : Border.all(
                  color: isDark ? AppColors.stoneGray : AppColors.mist,
                  width: 1,
                ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: backgroundColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: textColor),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// === PREMIUM SWITCH ===

class PremiumSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeColor;

  const PremiumSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
  });

  @override
  State<PremiumSwitch> createState() => _PremiumSwitchState();
}

class _PremiumSwitchState extends State<PremiumSwitch>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _positionAnimation;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: PremiumTheme.mediumAnimation,
      vsync: this,
    );

    _positionAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: PremiumTheme.premiumCurve),
    );

    _colorAnimation =
        ColorTween(
          begin: AppColors.cloud,
          end: widget.activeColor ?? AppColors.biLightBlue,
        ).animate(
          CurvedAnimation(
            parent: _controller,
            curve: PremiumTheme.premiumCurve,
          ),
        );

    if (widget.value) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(PremiumSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      if (widget.value) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double width = 52;
    const double height = 32;
    const double thumbSize = 24;

    return GestureDetector(
      onTap: () => widget.onChanged(!widget.value),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: _colorAnimation.value,
            borderRadius: BorderRadius.circular(height / 2),
            boxShadow: PremiumTheme.softShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Align(
              alignment: Alignment.lerp(
                Alignment.centerLeft,
                Alignment.centerRight,
                _positionAnimation.value,
              )!,
              child: Container(
                width: thumbSize,
                height: thumbSize,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(thumbSize / 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// === PREMIUM SECTION HEADER ===

class PremiumSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionText;
  final VoidCallback? onActionTap;
  final IconData? icon;

  const PremiumSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionText,
    this.onActionTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark ? AppColors.mist : AppColors.stoneGray,
                    ),
                  ),
                ],
              ],
            ),
          ),

          if (actionText != null && onActionTap != null)
            PremiumInkWell(
              onTap: onActionTap!,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      actionText!,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 12,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
