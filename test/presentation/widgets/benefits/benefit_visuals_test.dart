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

void main() {
  final nb = lookupAppLocalizations(const Locale('no'));

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
