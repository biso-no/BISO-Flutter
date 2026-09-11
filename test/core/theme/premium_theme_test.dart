import 'package:biso/core/theme/biso_colors.dart';
import 'package:biso/core/theme/biso_typography.dart';
import 'package:biso/core/theme/premium_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Museo Sans is used only at weight 300, only for large type', () {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      final t = BisoTypography.textTheme(platform);
      for (final style in [
        t.displayLarge,
        t.displayMedium,
        t.displaySmall,
        t.headlineLarge,
        t.headlineMedium,
      ]) {
        expect(style!.fontFamily, BisoTypography.museo);
        expect(style.fontWeight, FontWeight.w300);
      }
      for (final style in [
        t.headlineSmall,
        t.titleLarge,
        t.titleMedium,
        t.titleSmall,
        t.bodyLarge,
        t.bodyMedium,
        t.bodySmall,
        t.labelLarge,
        t.labelMedium,
        t.labelSmall,
      ]) {
        expect(style!.fontFamily, isNot(BisoTypography.museo));
      }
    }
  });

  test('iOS uses the system display face from 20 pt and text face below', () {
    final t = BisoTypography.textTheme(TargetPlatform.iOS);
    expect(t.headlineSmall!.fontFamily, 'CupertinoSystemDisplay');
    expect(t.titleLarge!.fontFamily, 'CupertinoSystemDisplay');
    expect(t.titleMedium!.fontFamily, 'CupertinoSystemText');
    expect(t.labelSmall!.fontFamily, 'CupertinoSystemText');
  });

  test('theme keeps per-style families instead of one global font', () {
    final theme = PremiumTheme.build(
      Brightness.light,
      platform: TargetPlatform.iOS,
    );
    expect(theme.textTheme.headlineLarge!.fontFamily, 'MuseoSans');
    expect(theme.textTheme.bodyMedium!.fontFamily, 'CupertinoSystemText');
  });

  test('themes carry their palette and map it into the color scheme', () {
    for (final (brightness, palette) in [
      (Brightness.light, BisoPalette.light),
      (Brightness.dark, BisoPalette.dark),
    ]) {
      final theme = PremiumTheme.build(brightness);
      expect(theme.extension<BisoPalette>(), same(palette));
      expect(theme.scaffoldBackgroundColor, palette.paper);
      expect(theme.colorScheme.primary, palette.primary);
      expect(theme.colorScheme.surface, palette.surface);
      expect(theme.colorScheme.error, palette.error);
      expect(theme.textTheme.bodyMedium!.color, palette.ink);
      final filled = theme.filledButtonTheme.style!;
      expect(filled.backgroundColor!.resolve({}), palette.primary);
      expect(filled.shape!.resolve({}), isA<StadiumBorder>());
      expect(
        theme.textButtonTheme.style!.foregroundColor!.resolve({}),
        palette.link,
      );
    }
  });
}
