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

  testWidgets(
    'a selected FilterChip label stays legible on the selected background, '
    'and an unselected chip keeps the ink look',
    (tester) async {
      final palette = BisoPalette.light;
      await tester.pumpWidget(
        MaterialApp(
          theme: PremiumTheme.build(
            Brightness.light,
            platform: TargetPlatform.iOS,
          ),
          home: const Scaffold(
            body: Column(
              children: [
                FilterChip(
                  selected: true,
                  onSelected: _noop,
                  label: Text('Selected'),
                ),
                FilterChip(
                  selected: false,
                  onSelected: _noop,
                  label: Text('Unselected'),
                ),
              ],
            ),
          ),
        ),
      );

      // The effective painted color, mirroring what a viewer actually sees:
      // this is exactly what would have stayed silently broken if only the
      // ChipThemeData properties were inspected instead of the render tree
      // (RawChip reads `labelStyle`, not `secondaryLabelStyle`, for a
      // selected chip's label).
      Color? labelColor(String label) => tester
          .widget<RichText>(
            find.descendant(
              of: find.text(label),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style
          ?.color;

      expect(labelColor('Selected'), palette.onPrimary);
      expect(labelColor('Unselected'), palette.ink);
    },
  );

  testWidgets(
    "the theme cannot make a selected chip's avatar icon state-aware: "
    "RawChip merges chipTheme.iconTheme into the avatar's IconTheme "
    'verbatim, without resolving a WidgetStateColor against the actual '
    'selected state (unlike labelStyle, which it does resolve above) — so '
    'chipTheme intentionally leaves iconTheme unset and a chip whose avatar '
    'must stay legible when selected sets its Icon color directly instead '
    '(see _TransitFilterChip in departures_screen.dart)',
    (tester) async {
      final theme = PremiumTheme.build(Brightness.light);
      expect(theme.chipTheme.iconTheme, isNull);
    },
  );
}

void _noop(bool _) {}
