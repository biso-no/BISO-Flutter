import 'package:biso/core/theme/biso_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final (name, palette) in [
    ('light', BisoPalette.light),
    ('dark', BisoPalette.dark),
  ]) {
    test('$name text tokens reach 4.5:1 on paper and surface', () {
      final text = {
        'ink': palette.ink,
        'muted': palette.muted,
        'link': palette.link,
        'success': palette.success,
        'warning': palette.warning,
        'error': palette.error,
      };
      for (final entry in text.entries) {
        for (final ground in [palette.paper, palette.surface]) {
          expect(
            contrast(entry.value, ground),
            greaterThanOrEqualTo(4.5),
            reason: '${entry.key} on $ground',
          );
        }
      }
      expect(
        contrast(palette.onPrimary, palette.primary),
        greaterThanOrEqualTo(4.5),
      );
    });
  }

  test('accent glyphs reach 3:1 on their fills', () {
    for (final accent in BisoAccent.values) {
      if (accent == BisoAccent.neutral) continue;
      expect(
        contrast(accent.fixedGlyph!, accent.fixedFill!),
        greaterThanOrEqualTo(3),
        reason: accent.name,
      );
    }
  });

  testWidgets('palette and neutral accent follow the theme extension', (
    tester,
  ) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [BisoPalette.dark],
        ),
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(BisoPalette.of(captured), same(BisoPalette.dark));
    expect(BisoAccent.neutral.fill(captured), BisoPalette.dark.surfaceRaised);
    expect(BisoAccent.neutral.glyph(captured), BisoPalette.dark.muted);
    expect(BisoAccent.gold.fill(captured), const Color(0xFFF2B42C));
  });

  testWidgets('palette falls back to brightness without an extension', (
    tester,
  ) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(BisoPalette.of(captured), same(BisoPalette.dark));
  });

  test('lerp reaches each end', () {
    expect(
      BisoPalette.light.lerp(BisoPalette.dark, 0).paper,
      BisoPalette.light.paper,
    );
    expect(
      BisoPalette.light.lerp(BisoPalette.dark, 1).link,
      BisoPalette.dark.link,
    );
  });
}
