import 'package:biso/core/theme/biso_colors.dart';
import 'package:biso/core/theme/biso_page.dart';
import 'package:biso/data/models/campus_benefit.dart';
import 'package:biso/presentation/widgets/benefits/benefit_perks.dart';
import 'package:biso/presentation/widgets/biso/biso_list.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

CampusBenefit _perk(
  String id,
  BenefitSection section,
  String title, {
  String? description,
}) => CampusBenefit(
  id: id,
  campusId: '3',
  section: section,
  title: BenefitText(nb: title),
  description: BenefitText(nb: description),
  redemptionType: BenefitRedemptionType.none,
);

/// Deliberately out of order, and with a business perk the app never shows.
final _perks = <BenefitSection, List<CampusBenefit>>{
  BenefitSection.safety: [
    _perk(
      's1',
      BenefitSection.safety,
      'Trygg varslingskanal',
      description: '<p>Si fra hvis noe er kritikkverdig.</p>',
    ),
  ],
  BenefitSection.business: [
    _perk('x1', BenefitSection.business, 'Stand på karrieredagen'),
  ],
  BenefitSection.career: [
    _perk(
      'c1',
      BenefitSection.career,
      'Intervju-coaching',
      description: 'Øv på intervju med en rådgiver.',
    ),
    _perk('c2', BenefitSection.career, 'CV-portrett til LinkedIn'),
  ],
  BenefitSection.social: [
    _perk('o1', BenefitSection.social, 'Winter Games på Storefjell'),
  ],
};

Future<void> _pump(
  WidgetTester tester, {
  Map<BenefitSection, List<CampusBenefit>>? perks,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => pumpBisoScreen(
  tester,
  BisoPage(
    title: 'Fordeler',
    slivers: [
      SliverToBoxAdapter(child: BenefitPerksSection(perks: perks ?? _perks)),
    ],
  ),
  locale: const Locale('no'),
  brightness: brightness,
  textScale: textScale,
);

void main() {
  testWidgets('perks show headings in order career, social, safety, with '
      'descriptions as subtitles', (tester) async {
    await _pump(tester);
    final career = tester.getTopLeft(find.text('Karrierefordeler')).dy;
    final social = tester.getTopLeft(find.text('Sosialt nettverk')).dy;
    final safety = tester.getTopLeft(find.text('Trygghet og støtte')).dy;
    expect(career, lessThan(social));
    expect(social, lessThan(safety));

    // Each heading sits above its own items.
    final coaching = tester.getTopLeft(find.text('Intervju-coaching')).dy;
    final winter = tester
        .getTopLeft(find.text('Winter Games på Storefjell'))
        .dy;
    final warn = tester.getTopLeft(find.text('Trygg varslingskanal')).dy;
    expect(career, lessThan(coaching));
    expect(coaching, lessThan(social));
    expect(social, lessThan(winter));
    expect(winter, lessThan(safety));
    expect(safety, lessThan(warn));

    // Descriptions are plain text under the title; a perk without one has
    // no subtitle.
    final rows = tester.widgetList<BisoListRow>(find.byType(BisoListRow));
    final byTitle = {for (final r in rows) r.title: r};
    expect(
      byTitle['Intervju-coaching']?.subtitle,
      'Øv på intervju med en rådgiver.',
    );
    expect(
      byTitle['Trygg varslingskanal']?.subtitle,
      'Si fra hvis noe er kritikkverdig.',
    );
    expect(byTitle['CV-portrett til LinkedIn']?.subtitle, isNull);
    expect(byTitle['Winter Games på Storefjell']?.subtitle, isNull);

    // One group per section, and the rows can't be tapped.
    expect(find.byType(BisoListGroup), findsNWidgets(3));
    for (final row in rows) {
      expect(row.onTap, isNull);
    }
  });

  testWidgets('the business section never shows', (tester) async {
    await _pump(tester);
    expect(find.text('Stand på karrieredagen'), findsNothing);
    expect(find.byType(BisoListRow), findsNWidgets(4));
  });

  testWidgets('a section without items has no heading', (tester) async {
    await _pump(
      tester,
      perks: {
        BenefitSection.social: const [],
        BenefitSection.safety: _perks[BenefitSection.safety]!,
      },
    );
    expect(find.text('Karrierefordeler'), findsNothing);
    expect(find.text('Sosialt nettverk'), findsNothing);
    expect(find.text('Trygghet og støtte'), findsOneWidget);
    expect(find.byType(BisoListGroup), findsOneWidget);
  });

  testWidgets('headings have a navy tile with a sky glyph; ticks are sky '
      'circles with a navy check', (tester) async {
    await _pump(tester);
    final palette = BisoPalette.light;
    for (final glyph in [
      CupertinoIcons.briefcase,
      CupertinoIcons.person_2,
      CupertinoIcons.shield,
    ]) {
      final icon = tester.widget<Icon>(find.byIcon(glyph));
      expect(icon.color, palette.sky);
      final tile =
          tester
                  .widget<DecoratedBox>(
                    find
                        .ancestor(
                          of: find.byIcon(glyph),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(tile.color, palette.deep);
      expect(tile.border, Border.all(color: palette.deepEdge));
      expect(
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.byIcon(glyph),
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            )
            .width,
        24,
      );
    }

    final ticks = find.byIcon(CupertinoIcons.checkmark);
    expect(ticks, findsNWidgets(4));
    for (final tick in tester.widgetList<Icon>(ticks)) {
      expect(tick.color, palette.deep);
    }
    final circle = find
        .ancestor(of: ticks.first, matching: find.byType(DecoratedBox))
        .first;
    final decoration =
        tester.widget<DecoratedBox>(circle).decoration as BoxDecoration;
    expect(decoration.color, palette.sky);
    expect(decoration.shape, BoxShape.circle);
    expect(tester.getSize(circle), const Size(20, 20));
  });

  testWidgets('a heading is read as a header', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Karrierefordeler')),
      isSemantics(label: 'Karrierefordeler', isHeader: true),
    );
    semantics.dispose();
  });

  for (final brightness in Brightness.values) {
    testWidgets('text scale 2.0 in $brightness: no overflow', (tester) async {
      await _pump(
        tester,
        brightness: brightness,
        textScale: 2,
        perks: {
          BenefitSection.career: [
            _perk(
              'c1',
              BenefitSection.career,
              'Eksklusive møter med bedrifter og speedintervju for medlemmer',
              description:
                  'Treff bedriftene som ansetter, få tips til søknaden og '
                  'øv på intervju sammen med andre studenter.',
            ),
          ],
          BenefitSection.safety: _perks[BenefitSection.safety]!,
        },
      );
      expect(tester.takeException(), isNull);
    });
  }
}
