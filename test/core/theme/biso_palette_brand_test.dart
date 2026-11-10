import 'package:biso/core/theme/biso_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (name, palette) in [
    ('light', BisoPalette.light),
    ('dark', BisoPalette.dark),
  ]) {
    test('$name carries the brand tokens', () {
      expect(palette.deep, const Color(0xFF001731));
      expect(palette.deepRaised, const Color(0xFF0B2747));
      expect(palette.deepEdge, const Color(0xFF12314F));
      expect(palette.deepMuted, const Color(0xFF93A7BB));
      expect(palette.sky, const Color(0xFF3DA9E0));
      expect(palette.marker, const Color(0xFFFECD45));
    });
  }

  test('brand tokens survive lerp and copyWith', () {
    final mid = BisoPalette.light.lerp(BisoPalette.dark, .5);
    expect(mid.marker, BisoPalette.light.marker);
    expect(mid.deep, BisoPalette.light.deep);
    final changed = BisoPalette.light.copyWith(sky: const Color(0xFF000000));
    expect(changed.sky, const Color(0xFF000000));
    expect(changed.marker, BisoPalette.light.marker);
  });
}
