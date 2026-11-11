import 'package:biso/core/theme/biso_colors.dart';
import 'package:biso/core/utils/benefit_highlight.dart';
import 'package:biso/data/models/campus_benefit.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/widgets/benefits/benefit_visuals.dart';
import 'package:biso/providers/benefits/benefit_showcase.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../../../helpers/biso_screen_harness.dart';

CampusBenefit _benefit({
  String? category,
  String? description,
  DateTime? publishEnd,
}) => CampusBenefit(
  id: 'b1',
  campusId: 'c1',
  section: BenefitSection.member,
  title: const BenefitText(nb: 'Tittel'),
  description: BenefitText(nb: description),
  category: category,
  publishEnd: publishEnd,
  redemptionType: BenefitRedemptionType.none,
);

/// The WCAG 2 contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final nb = lookupAppLocalizations(const Locale('no'));

  for (final (name, palette) in [
    ('light', BisoPalette.light),
    ('dark', BisoPalette.dark),
  ]) {
    test('blue text on the blue chip tint reads at 4.5:1 or more ($name)', () {
      final fill = Color.alphaBlend(benefitLinkTint(palette), palette.paper);
      expect(_contrast(palette.link, fill), greaterThanOrEqualTo(4.5));
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('on the page the reason chip is tinted BISO blue '
        '($brightness)', (tester) async {
      await pumpBisoScreen(
        tester,
        BenefitReasonChip(
          reason: FeaturedReason.pickedByBiso,
          benefit: _benefit(),
          onImage: false,
        ),
        inShell: false,
        brightness: brightness,
        locale: const Locale('no'),
      );
      final palette = brightness == Brightness.dark
          ? BisoPalette.dark
          : BisoPalette.light;
      final label = tester.widget<Text>(find.text('Valgt av BISO'));
      expect(label.style?.color, palette.link);
      final icon = tester.widget<Icon>(find.byIcon(CupertinoIcons.star_fill));
      expect(icon.color, palette.link);
      final box = tester.widget<DecoratedBox>(
        find.ancestor(
          of: find.text('Valgt av BISO'),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect((box.decoration as BoxDecoration).color, benefitLinkTint(palette));
    });
  }

  testWidgets('on a photo the reason chip stays navy with a sky icon', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      BenefitReasonChip(reason: FeaturedReason.isNew, benefit: _benefit()),
      inShell: false,
      locale: const Locale('no'),
    );
    const palette = BisoPalette.light;
    expect(
      tester.widget<Text>(find.text('Nytt')).style?.color,
      palette.deepMuted,
    );
    expect(
      tester.widget<Icon>(find.byIcon(CupertinoIcons.sparkles)).color,
      palette.sky,
    );
  });

  test('badge and value text use Norwegian number style', () {
    expect(
      benefitHighlightBadge(const BenefitHighlight.percent(25), nb),
      '−25 %',
    );
    expect(
      benefitHighlightValue(const BenefitHighlight.percent(25), nb),
      '25 %',
    );
    expect(
      benefitHighlightValue(const BenefitHighlight.price(150), nb),
      '150 kr',
    );
    expect(
      benefitHighlightBadge(const BenefitHighlight.price(150), nb),
      '150 kr',
    );
    expect(benefitHighlightBadge(const BenefitHighlight.free(), nb), 'Gratis');
  });

  test('category label and icon', () {
    expect(benefitCategoryLabel('food_drink', nb), 'Mat og drikke');
    expect(benefitCategoryLabel('unknown', nb), nb.benefitsCategoryOther);
    expect(benefitCategoryIcon('travel'), CupertinoIcons.airplane);
    expect(benefitCategoryIcon('unknown'), CupertinoIcons.sparkles);
  });

  testWidgets('image fallback shows the highlight value', (tester) async {
    await pumpBisoScreen(
      tester,
      BenefitImage(
        benefit: _benefit(description: '25% rabatt'),
        memCacheWidth: 400,
      ),
      inShell: false,
      locale: const Locale('no'),
    );
    expect(find.text('25 %'), findsOneWidget);
  });

  testWidgets('image fallback shows the category icon without a highlight', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      BenefitImage(benefit: _benefit(category: 'other'), memCacheWidth: 400),
      inShell: false,
      locale: const Locale('no'),
    );
    expect(find.byIcon(CupertinoIcons.sparkles), findsOneWidget);
  });

  testWidgets('without the highlight the fallback shows the category icon', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      BenefitImage(
        benefit: _benefit(category: 'events', description: '25 % rabatt'),
        memCacheWidth: 400,
        showHighlight: false,
      ),
      inShell: false,
      locale: const Locale('no'),
    );
    expect(find.byIcon(CupertinoIcons.calendar), findsOneWidget);
    expect(find.textContaining('25'), findsNothing);
  });

  testWidgets('ending soon chip names the Oslo day', (tester) async {
    await pumpBisoScreen(
      tester,
      BenefitReasonChip(
        reason: FeaturedReason.endingSoon,
        benefit: _benefit(publishEnd: DateTime.utc(2026, 11, 30, 22, 59, 59)),
      ),
      inShell: false,
      locale: const Locale('no'),
    );
    final day = DateFormat('d. MMM', 'no').format(DateTime.utc(2026, 11, 30));
    expect(find.text('Slutter $day'), findsOneWidget);
  });

  testWidgets('badge draws its label', (tester) async {
    await pumpBisoScreen(tester, const BenefitBadge('25 %'), inShell: false);
    expect(find.text('25 %'), findsOneWidget);
  });
}
