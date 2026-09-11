import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import 'biso_colors.dart';
import 'biso_typography.dart';

/// BISO foundations. Colors come from [BisoPalette] and type from
/// [BisoTypography]; component themes only arrange those tokens.
class PremiumTheme {
  static final lightTheme = build(Brightness.light);
  static final darkTheme = build(Brightness.dark);

  static ThemeData build(Brightness brightness, {TargetPlatform? platform}) {
    final dark = brightness == Brightness.dark;
    final p = dark ? BisoPalette.dark : BisoPalette.light;
    final text = BisoTypography.textTheme(
      platform ?? defaultTargetPlatform,
    ).apply(bodyColor: p.ink, displayColor: p.ink);
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.biNavy,
      brightness: brightness,
      primary: p.primary,
      onPrimary: p.onPrimary,
      secondary: AppColors.biLightBlue,
      onSecondary: AppColors.biNavy,
      error: p.error,
      surface: p.surface,
      onSurface: p.ink,
      onSurfaceVariant: p.muted,
      outline: p.muted,
      outlineVariant: p.hairline,
      surfaceContainerHighest: p.surfaceRaised,
    );
    const pill = StadiumBorder();
    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    );
    OutlineInputBorder field([Color? color, double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: color == null
              ? BorderSide.none
              : BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      platform: platform,
      colorScheme: scheme,
      textTheme: text,
      scaffoldBackgroundColor: p.paper,
      extensions: [p],
      splashFactory: NoSplash.splashFactory,
      highlightColor: p.ink.withValues(alpha: 0.06),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: p.paper,
        foregroundColor: p.ink,
        centerTitle: true,
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: text.titleSmall?.copyWith(fontSize: 17),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: rounded,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          minimumSize: const Size(44, 50),
          shape: pill,
          textStyle: text.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          minimumSize: const Size(44, 50),
          shape: pill,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: p.surfaceRaised,
          foregroundColor: p.ink,
          side: BorderSide.none,
          minimumSize: const Size(44, 50),
          shape: pill,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.link,
          minimumSize: const Size(44, 44),
          textStyle: text.bodyLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: p.ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceRaised,
        border: field(),
        enabledBorder: field(),
        focusedBorder: field(p.link, 1.5),
        errorBorder: field(p.error),
        focusedErrorBorder: field(p.error, 1.5),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: text.bodyLarge?.copyWith(color: p.muted),
        labelStyle: text.bodyLarge?.copyWith(color: p.muted),
        errorStyle: text.bodySmall?.copyWith(color: p.error),
      ),
      dividerTheme: DividerThemeData(
        color: p.hairline,
        thickness: 0.5,
        space: 0.5,
      ),
      iconTheme: IconThemeData(color: p.ink, size: 22),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        iconColor: p.muted,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodyMedium?.copyWith(color: p.muted),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? p.link : null,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceRaised,
        selectedColor: p.primary,
        labelStyle: text.labelMedium?.copyWith(color: p.ink),
        secondaryLabelStyle: text.labelMedium?.copyWith(color: p.onPrimary),
        side: BorderSide.none,
        shape: pill,
        showCheckmark: false,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: rounded,
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium?.copyWith(color: p.muted),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: p.paper),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.link,
        linearTrackColor: p.surfaceRaised,
      ),
    );
  }

  // === PREMIUM SHADOW SYSTEM ===
  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: AppColors.shadowLight,
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get mediumShadow => [
    BoxShadow(
      color: AppColors.shadowMedium,
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: AppColors.shadowLight,
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> get strongShadow => [
    BoxShadow(
      color: AppColors.shadowHeavy,
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: AppColors.shadowMedium,
      blurRadius: 32,
      offset: const Offset(0, 16),
    ),
  ];

  // === GLASS MORPHISM EFFECTS ===
  static BoxDecoration glassContainer({
    Color? color,
    double blur = 20,
    double opacity = 0.1,
    BorderRadius? borderRadius,
    List<Color>? gradientColors,
  }) {
    return BoxDecoration(
      borderRadius: borderRadius ?? BorderRadius.circular(20),
      gradient: gradientColors != null
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            )
          : null,
      color: color ?? AppColors.white.withValues(alpha: opacity),
      boxShadow: mediumShadow,
      border: Border.all(
        color: AppColors.white.withValues(alpha: 0.2),
        width: 1,
      ),
    );
  }

  // === ANIMATION CURVES ===
  static const Curve premiumCurve = Curves.easeInOutCubicEmphasized;
  static const Duration fastAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 300);
  static const Duration slowAnimation = Duration(milliseconds: 500);
}
