import 'package:biso/core/theme/biso_glass.dart';
import 'package:biso/core/theme/premium_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BisoGlassCard opaque content surface', () {
    testWidgets(
      'gives a tappable ListTile child a Material to paint its background and '
      'ink on, rather than leaving the card decoration between the tile and '
      'the nearest Material ancestor',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BisoGlassCard(
                borderRadius: 16,

                // ListTile only checks for a hidden background when it is
                // interactive or opaque, which is exactly how the profile and
                // explore screens use it inside this card.
                child: ListTile(
                  title: const Text('Edit profile'),
                  onTap: () {},
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('still paints the card background itself', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: PremiumTheme.lightTheme,
          home: Scaffold(
            body: BisoGlassCard(borderRadius: 16, child: SizedBox.shrink()),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(BisoGlassCard),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, Colors.white);
      expect(decoration.boxShadow, isNotEmpty);
    });
  });
}
