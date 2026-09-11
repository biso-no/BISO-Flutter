import 'package:flutter/material.dart';

/// Museo Sans exists only as weight 300, so it is reserved for large type
/// where a light weight reads well. Everything else uses the platform's UI
/// face with real weights, which avoids synthesized bold.
class BisoTypography {
  BisoTypography._();

  static const museo = 'MuseoSans';

  static TextTheme textTheme(TargetPlatform platform) {
    final apple =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    final display = apple ? 'CupertinoSystemDisplay' : null;
    final text = apple ? 'CupertinoSystemText' : null;

    TextStyle museoStyle(double size, double height, double spacing) =>
        TextStyle(
          fontFamily: museo,
          fontSize: size,
          fontWeight: FontWeight.w300,
          height: height,
          letterSpacing: spacing,
        );

    TextStyle system(
      String? family,
      double size,
      FontWeight weight,
      double height, [
      double spacing = 0,
    ]) => TextStyle(
      fontFamily: family,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: spacing,
    );

    return TextTheme(
      displayLarge: museoStyle(57, 1.12, -1.0),
      displayMedium: museoStyle(45, 1.16, -0.8),
      displaySmall: museoStyle(36, 1.2, -0.6),
      headlineLarge: museoStyle(34, 1.18, -0.5),
      headlineMedium: museoStyle(28, 1.2, -0.3),
      headlineSmall: system(display, 22, FontWeight.w700, 1.25, -0.2),
      titleLarge: system(display, 20, FontWeight.w600, 1.25, -0.2),
      titleMedium: system(text, 17, FontWeight.w400, 1.3, -0.2),
      titleSmall: system(text, 15, FontWeight.w600, 1.33, -0.1),
      bodyLarge: system(text, 17, FontWeight.w400, 1.35, -0.2),
      bodyMedium: system(text, 15, FontWeight.w400, 1.35, -0.1),
      bodySmall: system(text, 13, FontWeight.w400, 1.3),
      labelLarge: system(text, 17, FontWeight.w600, 1.2, -0.2),
      labelMedium: system(text, 13, FontWeight.w500, 1.25),
      labelSmall: system(text, 11, FontWeight.w500, 1.2, 0.1),
    );
  }
}
