import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: _lightColorScheme,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: _appBarTheme,
      elevatedButtonTheme: _elevatedButtonTheme,
      textButtonTheme: _textButtonTheme,
      outlinedButtonTheme: _outlinedButtonTheme,
      inputDecorationTheme: _inputDecorationTheme,
      cardTheme: _cardThemeData,
      bottomNavigationBarTheme: _bottomNavigationBarThemeData,
      tabBarTheme: _tabBarThemeData,
      dividerTheme: _dividerThemeData,
      listTileTheme: _listTileThemeData,
      textTheme: _textTheme,
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: _darkColorScheme,
      fontFamily: 'Inter',
      scaffoldBackgroundColor:
          AppColors.backgroundDark, // Premium dark background
      appBarTheme: _appBarTheme.copyWith(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.onBackgroundDark,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: _appBarTheme.titleTextStyle?.copyWith(
          color: AppColors.onBackgroundDark,
        ),
      ),
      elevatedButtonTheme: _elevatedButtonTheme,
      textButtonTheme: _textButtonTheme,
      outlinedButtonTheme: _outlinedButtonTheme,
      inputDecorationTheme: _inputDecorationTheme.copyWith(
        fillColor: AppColors.surfaceDark,
        hintStyle: const TextStyle(
          color: AppColors.mist,
          fontSize: 16,
          fontFamily: 'Inter',
        ),
        labelStyle: const TextStyle(
          color: AppColors.onSurfaceDark,
          fontSize: 16,
          fontFamily: 'Inter',
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.outlineDark),
        ),
      ),
      cardTheme: _cardThemeData.copyWith(
        color: AppColors.surfaceDark,
        shadowColor: AppColors.shadowHeavy,
        elevation: 2,
      ),
      bottomNavigationBarTheme: _bottomNavigationBarThemeData.copyWith(
        backgroundColor: AppColors.backgroundDark,
        selectedItemColor: AppColors.crystalBlue,
        unselectedItemColor: AppColors.mist,
      ),
      tabBarTheme: _tabBarThemeData.copyWith(
        unselectedLabelColor: AppColors.mist,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.outlineVariantDark,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: _listTileThemeData.copyWith(
        iconColor: AppColors.mist,
      ),
      textTheme: _textTheme.apply(
        bodyColor: AppColors.onBackgroundDark,
        displayColor: AppColors.onBackgroundDark,
      ),
    );
  }

  static const ColorScheme _lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.crystalBlue, // Your brand light blue
    onPrimary: AppColors.white,
    secondary: AppColors.warmGold, // Sophisticated gold
    onSecondary: AppColors.richNavy, // Your brand navy
    tertiary: AppColors.emeraldGreen, // Premium accent
    onTertiary: AppColors.white,
    error: AppColors.error,
    onError: AppColors.white,
    surface: AppColors.surface,
    onSurface: AppColors.onSurface,
    surfaceContainerHighest: AppColors.surfaceVariant,
    onSurfaceVariant: AppColors.onSurfaceVariant,
    outline: AppColors.outline,
    outlineVariant: AppColors.outlineVariant,
    shadow: AppColors.shadowMedium,
    scrim: AppColors.overlayHeavy,
    inverseSurface: AppColors.smokeGray,
    onInverseSurface: AppColors.cloud,
    inversePrimary: AppColors.skyBlue,
    surfaceTint: AppColors.crystalBlue,
  );

  static const ColorScheme _darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.crystalBlue, // Consistent brand blue
    onPrimary: AppColors.charcoalBlack,
    secondary: AppColors.sunGold, // Bright gold for dark theme
    onSecondary: AppColors.charcoalBlack,
    tertiary: AppColors.emeraldGreen,
    onTertiary: AppColors.charcoalBlack,
    error: AppColors.error,
    onError: AppColors.white,
    surface: AppColors.surfaceDark,
    onSurface: AppColors.onSurfaceDark,
    surfaceContainerHighest: AppColors.stoneGray,
    onSurfaceVariant: AppColors.mist,
    outline: AppColors.outlineDark,
    outlineVariant: AppColors.outlineVariantDark,
    shadow: AppColors.shadowHeavy,
    scrim: AppColors.overlayHeavy,
    inverseSurface: AppColors.cloud,
    onInverseSurface: AppColors.charcoalBlack,
    inversePrimary: AppColors.richNavy,
    surfaceTint: AppColors.crystalBlue,
  );

  static const AppBarTheme _appBarTheme = AppBarTheme(
    elevation: 0,
    backgroundColor: AppColors.background,
    foregroundColor: AppColors.onBackground,
    surfaceTintColor: Colors.transparent,
    systemOverlayStyle: SystemUiOverlayStyle.dark,
    titleTextStyle: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: AppColors.onBackground,
      fontFamily: 'Inter',
    ),
  );

  static final ElevatedButtonThemeData _elevatedButtonTheme =
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.crystalBlue, // Premium brand blue
          foregroundColor: AppColors.white,
          elevation: 0,
          shadowColor: AppColors.shadowMedium,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
        ),
      );

  static final TextButtonThemeData _textButtonTheme = TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.crystalBlue, // Consistent brand blue
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        fontFamily: 'Inter',
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );

  static final OutlinedButtonThemeData _outlinedButtonTheme =
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.crystalBlue,
          side: const BorderSide(color: AppColors.crystalBlue, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
        ),
      );

  static final InputDecorationTheme _inputDecorationTheme =
      InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.crystalBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: const TextStyle(
          color: AppColors.onSurfaceVariant,
          fontSize: 16,
          fontFamily: 'Inter',
        ),
        labelStyle: const TextStyle(
          color: AppColors.onSurface,
          fontSize: 16,
          fontFamily: 'Inter',
        ),
      );

  static final CardThemeData _cardThemeData = CardThemeData(
    elevation: 2, // Subtle elevation for depth
    shadowColor: AppColors.shadowLight, // Premium shadow
    color: AppColors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16), // More premium radius
      side: const BorderSide(color: AppColors.outlineVariant, width: 0.5),
    ),
    margin: EdgeInsets.zero,
  );

  static const BottomNavigationBarThemeData _bottomNavigationBarThemeData =
      BottomNavigationBarThemeData(
        backgroundColor: AppColors.white,
        selectedItemColor: AppColors.crystalBlue,
        unselectedItemColor: AppColors.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 12, // More pronounced elevation
      );

  static const TabBarThemeData _tabBarThemeData = TabBarThemeData(
    labelColor: AppColors.crystalBlue,
    unselectedLabelColor: AppColors.onSurfaceVariant,
    indicatorColor: AppColors.crystalBlue,
    indicatorSize: TabBarIndicatorSize.tab,
    labelStyle: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      fontFamily: 'Inter',
    ),
    unselectedLabelStyle: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      fontFamily: 'Inter',
    ),
  );

  static const DividerThemeData _dividerThemeData = DividerThemeData(
    color: AppColors.outlineVariant,
    thickness: 1,
    space: 1,
  );

  static const ListTileThemeData _listTileThemeData = ListTileThemeData(
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
  );

  static const TextTheme _textTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      color: AppColors.onBackground,
      fontFamily: 'Inter',
      height: 1.2,
    ),
    displayMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: AppColors.onBackground,
      fontFamily: 'Inter',
      height: 1.2,
    ),
    displaySmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: AppColors.onBackground,
      fontFamily: 'Inter',
      height: 1.3,
    ),
    headlineLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: AppColors.onBackground,
      fontFamily: 'Inter',
      height: 1.3,
    ),
    headlineMedium: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: AppColors.onBackground,
      fontFamily: 'Inter',
      height: 1.3,
    ),
    headlineSmall: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: AppColors.onBackground,
      fontFamily: 'Inter',
      height: 1.4,
    ),
    titleLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: AppColors.onBackground,
      fontFamily: 'Inter',
      height: 1.4,
    ),
    titleMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: AppColors.onBackground,
      fontFamily: 'Inter',
      height: 1.4,
    ),
    titleSmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.onBackground,
      fontFamily: 'Inter',
      height: 1.4,
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: AppColors.onSurface,
      fontFamily: 'Inter',
      height: 1.5,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: AppColors.onSurface,
      fontFamily: 'Inter',
      height: 1.5,
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: AppColors.onSurfaceVariant,
      fontFamily: 'Inter',
      height: 1.4,
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: AppColors.onSurface,
      fontFamily: 'Inter',
      height: 1.4,
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: AppColors.onSurface,
      fontFamily: 'Inter',
      height: 1.4,
    ),
    labelSmall: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w500,
      color: AppColors.onSurfaceVariant,
      fontFamily: 'Inter',
      height: 1.4,
    ),
  );
}
