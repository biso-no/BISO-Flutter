import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';

/// Premium BISO Theme System
///
/// A sophisticated, luxury design system that moves beyond Material Design
/// to create an exclusive experience for BI Business School students.
///
/// Key Principles:
/// - Warm, cozy, super premium feel
/// - Glass morphism and elegant shadows
/// - BI brand colors as foundation
/// - Sophisticated typography
/// - Subtle animations and micro-interactions
class PremiumTheme {
  // === CORE THEME CONFIGURATION ===

  static ThemeData lightTheme = ThemeData(
    useMaterial3: false, // Disable Material 3 for custom design
    brightness: Brightness.light,

    // === COLOR SCHEME ===
    colorScheme: const ColorScheme.light(
      // Primary uses the warm light blue from BI
      primary: AppColors.biLightBlue,
      onPrimary: Colors.white,

      // Secondary uses sophisticated navy
      secondary: AppColors.biNavy,
      onSecondary: Colors.white,

      // Background and surfaces with warm premium tones
      surface: AppColors.pearl,
      onSurface: AppColors.charcoalBlack,
      surfaceContainerHighest: AppColors.cloud,

      // Error states with sophisticated reds
      error: Color(0xFFDC2626),
      onError: Colors.white,

      // Outline uses subtle premium grays
      outline: AppColors.mist,
      outlineVariant: AppColors.cloud,
    ),

    // === TYPOGRAPHY SYSTEM ===
    textTheme: _premiumTextTheme,

    // === APP BAR STYLING ===
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: AppColors.charcoalBlack,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      centerTitle: false,
      titleTextStyle: _premiumTextTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.charcoalBlack,
      ),
    ),

    // === CARD STYLING ===
    cardTheme: CardThemeData(
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: AppColors.white,
      surfaceTintColor: Colors.transparent,
    ),

    // === BUTTON STYLING ===
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        shadowColor: Colors.transparent,
        backgroundColor: AppColors.biLightBlue,
        foregroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: _premiumTextTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.biLightBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: _premiumTextTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.biLightBlue,
        side: const BorderSide(color: AppColors.biLightBlue, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: _premiumTextTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
    ),

    // === INPUT STYLING ===
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.pearl,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.cloud, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.biLightBlue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.error, width: 1),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      hintStyle: _premiumTextTheme.bodyLarge?.copyWith(color: AppColors.mist),
      labelStyle: _premiumTextTheme.bodyMedium?.copyWith(
        color: AppColors.stoneGray,
        fontWeight: FontWeight.w500,
      ),
    ),

    // === DIVIDER STYLING ===
    dividerTheme: const DividerThemeData(
      color: AppColors.cloud,
      thickness: 1,
      space: 1,
    ),

    // === CHIP STYLING ===
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.cloud,
      labelStyle: _premiumTextTheme.bodySmall?.copyWith(
        color: AppColors.stoneGray,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),

    // === SCAFFOLD STYLING ===
    scaffoldBackgroundColor: AppColors.pearl,

    // === BOTTOM SHEET STYLING ===
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      elevation: 0,
      shadowColor: Colors.transparent,
    ),

    // === DIALOG STYLING ===
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.white,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: _premiumTextTheme.headlineSmall?.copyWith(
        color: AppColors.charcoalBlack,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: _premiumTextTheme.bodyLarge?.copyWith(
        color: AppColors.stoneGray,
        height: 1.5,
      ),
    ),

    // === SWITCH STYLING ===
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.white;
        }
        return AppColors.mist;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.biLightBlue;
        }
        return AppColors.cloud;
      }),
    ),

    // === PROGRESS INDICATOR STYLING ===
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.biLightBlue,
      linearTrackColor: AppColors.cloud,
      circularTrackColor: AppColors.cloud,
    ),

    // === ICON STYLING ===
    iconTheme: const IconThemeData(color: AppColors.stoneGray, size: 24),

    // === LIST TILE STYLING ===
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      tileColor: AppColors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      titleTextStyle: _premiumTextTheme.titleMedium?.copyWith(
        color: AppColors.charcoalBlack,
        fontWeight: FontWeight.w500,
      ),
      subtitleTextStyle: _premiumTextTheme.bodyMedium?.copyWith(
        color: AppColors.stoneGray,
      ),
      iconColor: AppColors.stoneGray,
    ),

    // === NAVIGATION BAR (disable Material styling) ===
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: AppColors.biLightBlue,
      unselectedItemColor: AppColors.mist,
    ),
  );

  // === DARK THEME ===
  static ThemeData darkTheme = ThemeData(
    useMaterial3: false,
    brightness: Brightness.dark,

    colorScheme: const ColorScheme.dark(
      // Primary uses the warm light blue
      primary: AppColors.biLightBlue,
      onPrimary: AppColors.biNavy,

      // Secondary uses the navy
      secondary: AppColors.biNavy,
      onSecondary: Colors.white,

      // Dark surfaces with premium navy tones
      surface: AppColors.charcoalBlack,
      onSurface: AppColors.pearl,
      surfaceContainerHighest: AppColors.smokeGray,

      // Error states
      error: Color(0xFFEF4444),
      onError: Colors.white,

      // Outline uses subtle grays
      outline: AppColors.stoneGray,
      outlineVariant: AppColors.smokeGray,
    ),

    textTheme: _premiumTextTheme.apply(
      bodyColor: AppColors.pearl,
      displayColor: AppColors.pearl,
    ),

    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: AppColors.pearl,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      centerTitle: false,
      titleTextStyle: _premiumTextTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.pearl,
      ),
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: AppColors.smokeGray,
      surfaceTintColor: Colors.transparent,
    ),

    scaffoldBackgroundColor: AppColors.charcoalBlack,

    // === DARK CARD STYLING (already set above) ===

    // === DARK BUTTON STYLING ===
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        shadowColor: Colors.transparent,
        backgroundColor: AppColors.biLightBlue,
        foregroundColor: AppColors.biNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: _premiumTextTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // === DARK BOTTOM SHEET STYLING ===
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.smokeGray,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      elevation: 0,
      shadowColor: Colors.transparent,
    ),

    // === DARK DIALOG STYLING ===
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.smokeGray,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: _premiumTextTheme.headlineSmall?.copyWith(
        color: AppColors.pearl,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: _premiumTextTheme.bodyLarge?.copyWith(
        color: AppColors.mist,
        height: 1.5,
      ),
    ),

    // === DARK SWITCH STYLING ===
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.pearl;
        }
        return AppColors.stoneGray;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.biLightBlue;
        }
        return AppColors.smokeGray;
      }),
    ),

    // === DARK ICON STYLING ===
    iconTheme: const IconThemeData(color: AppColors.mist, size: 24),

    // === DARK LIST TILE STYLING ===
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      tileColor: AppColors.smokeGray,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      titleTextStyle: _premiumTextTheme.titleMedium?.copyWith(
        color: AppColors.pearl,
        fontWeight: FontWeight.w500,
      ),
      subtitleTextStyle: _premiumTextTheme.bodyMedium?.copyWith(
        color: AppColors.mist,
      ),
      iconColor: AppColors.mist,
    ),

    // === DARK DIVIDER STYLING ===
    dividerTheme: const DividerThemeData(
      color: AppColors.smokeGray,
      thickness: 1,
      space: 1,
    ),

    // === DARK CHIP STYLING ===
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.smokeGray,
      labelStyle: _premiumTextTheme.bodySmall?.copyWith(
        color: AppColors.mist,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),

    // === DARK PROGRESS INDICATOR STYLING ===
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.biLightBlue,
      linearTrackColor: AppColors.smokeGray,
      circularTrackColor: AppColors.smokeGray,
    ),

    // Dark theme input styling
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.smokeGray,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.stoneGray, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.biLightBlue, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      hintStyle: _premiumTextTheme.bodyLarge?.copyWith(
        color: AppColors.stoneGray,
      ),
      labelStyle: _premiumTextTheme.bodyMedium?.copyWith(
        color: AppColors.mist,
        fontWeight: FontWeight.w500,
      ),
    ),
  );

  // === PREMIUM TYPOGRAPHY SYSTEM ===
  static const TextTheme _premiumTextTheme = TextTheme(
    // Display styles - for hero content
    displayLarge: TextStyle(
      fontSize: 57,
      fontWeight: FontWeight.w300,
      letterSpacing: -0.25,
      height: 1.12,
      fontFamily: 'SF Pro Display', // iOS-style font for premium feel
    ),
    displayMedium: TextStyle(
      fontSize: 45,
      fontWeight: FontWeight.w300,
      letterSpacing: 0,
      height: 1.16,
      fontFamily: 'SF Pro Display',
    ),
    displaySmall: TextStyle(
      fontSize: 36,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.22,
      fontFamily: 'SF Pro Display',
    ),

    // Headline styles - for section headers
    headlineLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      height: 1.25,
      fontFamily: 'SF Pro Display',
    ),
    headlineMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      height: 1.29,
      fontFamily: 'SF Pro Display',
    ),
    headlineSmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      height: 1.33,
      fontFamily: 'SF Pro Display',
    ),

    // Title styles - for cards and lists
    titleLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
      height: 1.27,
      fontFamily: 'SF Pro Text',
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.15,
      height: 1.50,
      fontFamily: 'SF Pro Text',
    ),
    titleSmall: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
      height: 1.43,
      fontFamily: 'SF Pro Text',
    ),

    // Label styles - for buttons and chips
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      height: 1.43,
      fontFamily: 'SF Pro Text',
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      height: 1.33,
      fontFamily: 'SF Pro Text',
    ),
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      height: 1.45,
      fontFamily: 'SF Pro Text',
    ),

    // Body styles - for content
    bodyLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.15,
      height: 1.50,
      fontFamily: 'SF Pro Text',
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.25,
      height: 1.43,
      fontFamily: 'SF Pro Text',
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.4,
      height: 1.33,
      fontFamily: 'SF Pro Text',
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
      border: Border.all(color: AppColors.white.withValues(alpha: 0.2), width: 1),
    );
  }

  // === ANIMATION CURVES ===
  static const Curve premiumCurve = Curves.easeInOutCubicEmphasized;
  static const Duration fastAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 300);
  static const Duration slowAnimation = Duration(milliseconds: 500);
}
