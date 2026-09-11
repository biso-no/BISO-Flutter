import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';

/// BISO foundations. Keep the established API while screens adopt the refresh.
class PremiumTheme {
  static final lightTheme = _theme(Brightness.light);
  static final darkTheme = _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFF1F6FA) : AppColors.biNavy;
    final muted = dark ? const Color(0xFFABC0D0) : const Color(0xFF526579);
    final surface = dark ? const Color(0xFF102C46) : Colors.white;
    final paper = dark ? const Color(0xFF071B2E) : const Color(0xFFF4F7FA);
    final line = dark ? const Color(0xFF294158) : const Color(0xFFDCE5EC);
    final primary = dark ? AppColors.biLightBlue : AppColors.biNavy;
    final text = _premiumTextTheme.apply(bodyColor: ink, displayColor: ink);
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.biNavy,
      brightness: brightness,
      primary: primary,
      onPrimary: dark ? AppColors.biNavy : Colors.white,
      secondary: AppColors.biLightBlue,
      onSecondary: AppColors.biNavy,
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: muted,
      outline: muted,
      outlineVariant: line,
      surfaceContainerHighest: dark
          ? const Color(0xFF183750)
          : const Color(0xFFEAF0F5),
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'MuseoSans',
      textTheme: text,
      scaffoldBackgroundColor: paper,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: paper,
        foregroundColor: ink,
        centerTitle: false,
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: shape,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(44, 50),
          shape: const StadiumBorder(),
          textStyle: text.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 50),
          shape: const StadiumBorder(),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(44, 44),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: line),
          minimumSize: const Size(44, 50),
          shape: const StadiumBorder(),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.biLightBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        hintStyle: text.bodyLarge?.copyWith(color: muted),
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 0.5, space: 1),
      iconTheme: IconThemeData(color: ink, size: 24),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        iconColor: muted,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodyMedium?.copyWith(color: muted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(backgroundColor: surface, shape: shape),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: AppColors.biLightBlue.withValues(alpha: 0.18),
        side: BorderSide(color: line),
        shape: const StadiumBorder(),
        labelStyle: text.labelLarge?.copyWith(color: ink),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.biLightBlue,
      ),
    );
  }

  // === PREMIUM TYPOGRAPHY SYSTEM ===
  static const TextTheme _premiumTextTheme = TextTheme(
    // Display styles - for hero content
    displayLarge: TextStyle(
      fontSize: 57,
      fontWeight: FontWeight.w300,
      letterSpacing: -0.25,
      height: 1.12,
      fontFamily: 'MuseoSans', // iOS-style font for premium feel
    ),
    displayMedium: TextStyle(
      fontSize: 45,
      fontWeight: FontWeight.w300,
      letterSpacing: 0,
      height: 1.16,
      fontFamily: 'MuseoSans',
    ),
    displaySmall: TextStyle(
      fontSize: 36,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.22,
      fontFamily: 'MuseoSans',
    ),

    // Headline styles - for section headers
    headlineLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      height: 1.25,
      fontFamily: 'MuseoSans',
    ),
    headlineMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      height: 1.29,
      fontFamily: 'MuseoSans',
    ),
    headlineSmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      height: 1.33,
      fontFamily: 'MuseoSans',
    ),

    // Title styles - for cards and lists
    titleLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
      height: 1.27,
      fontFamily: 'MuseoSans',
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.15,
      height: 1.50,
      fontFamily: 'MuseoSans',
    ),
    titleSmall: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
      height: 1.43,
      fontFamily: 'MuseoSans',
    ),

    // Label styles - for buttons and chips
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      height: 1.43,
      fontFamily: 'MuseoSans',
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      height: 1.33,
      fontFamily: 'MuseoSans',
    ),
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      height: 1.45,
      fontFamily: 'MuseoSans',
    ),

    // Body styles - for content
    bodyLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.15,
      height: 1.50,
      fontFamily: 'MuseoSans',
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.25,
      height: 1.43,
      fontFamily: 'MuseoSans',
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.4,
      height: 1.33,
      fontFamily: 'MuseoSans',
    ),
  );

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
