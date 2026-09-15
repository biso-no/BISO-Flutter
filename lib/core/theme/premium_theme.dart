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
        // A selected chip swaps its background to `p.primary`; the label
        // must swap to `p.onPrimary` in step or it renders in `p.ink` on top
        // of itself. `RawChip` explicitly resolves `labelStyle`'s color
        // against the chip's live `WidgetState`s before painting (see
        // `resolvedLabelColor` in `chip.dart`), so a `WidgetStateColor` here
        // works correctly — unlike `secondaryLabelStyle`, which current
        // Flutter no longer applies for the selected state at all.
        labelStyle: text.labelMedium?.copyWith(
          color: WidgetStateColor.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? p.onPrimary : p.ink,
          ),
        ),
        secondaryLabelStyle: text.labelMedium?.copyWith(color: p.onPrimary),
        // NOT the same fix for a selected chip's avatar icon: unlike
        // `labelStyle`, `RawChip` merges `chipTheme.iconTheme` into the
        // avatar's `IconTheme` as-is (see the `avatar` local in
        // `RawChip.build`) — it never resolves a `WidgetStateColor` here
        // against the chip's actual selected state, so a `WidgetStateColor`
        // in this slot silently paints as its unselected branch for every
        // chip, selected or not. The theme genuinely cannot express a
        // selected-state-aware avatar color, so a chip whose avatar must
        // stay legible when selected (e.g. `_TransitFilterChip` in
        // departures_screen.dart) sets its `Icon`'s `color` directly instead
        // of relying on `iconTheme` here.
        checkmarkColor: p.onPrimary,
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
}
