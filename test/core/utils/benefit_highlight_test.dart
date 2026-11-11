import 'package:biso/core/utils/benefit_highlight.dart';
import 'package:biso/data/models/campus_benefit.dart';
import 'package:flutter_test/flutter_test.dart';

CampusBenefit b({String title = 'X', String? description}) => CampusBenefit(
  id: 'b1',
  campusId: 'oslo',
  section: BenefitSection.member,
  title: BenefitText(nb: title),
  description: BenefitText(nb: description),
  redemptionType: BenefitRedemptionType.none,
);

void main() {
  test('finds a percentage in the description', () {
    expect(
      benefitHighlightOf(
        b(
          title: 'GRAFFI GRILL',
          description: '25% rabatt på hele menyen for biso-medlemmer',
        ),
        'nb',
      ),
      const BenefitHighlight.percent(25),
    );
  });

  test('finds a percentage in the title', () {
    expect(
      benefitHighlightOf(b(title: '20% Rabatt på Los Tacos'), 'nb'),
      const BenefitHighlight.percent(20),
    );
  });

  test('finds free', () {
    expect(
      benefitHighlightOf(
        b(
          title: 'Club Tempo',
          description: 'Gratis inngang for alle BISO-medlemmer',
        ),
        'nb',
      ),
      const BenefitHighlight.free(),
    );
    expect(
      benefitHighlightOf(b(title: 'Free entry'), 'en'),
      const BenefitHighlight.free(),
    );
  });

  test('finds a price', () {
    expect(
      benefitHighlightOf(
        b(title: 'RUSH', description: '150kr for 2 timer hopping'),
        'nb',
      ),
      const BenefitHighlight.price(150),
    );
    expect(
      benefitHighlightOf(
        b(title: 'BABA', description: '149 kr for sandwich, 119kr for acai'),
        'nb',
      ),
      const BenefitHighlight.price(149),
    );
    expect(
      benefitHighlightOf(b(title: 'Kino', description: 'Billett 75,-'), 'nb'),
      const BenefitHighlight.price(75),
    );
  });

  test('the title wins over the description', () {
    expect(
      benefitHighlightOf(
        b(title: '10 % hos Peppes', description: 'Gratis brus'),
        'nb',
      ),
      const BenefitHighlight.percent(10),
    );
  });

  test('markup is read as plain text', () {
    expect(
      benefitHighlightOf(
        b(description: '<p>25<strong>%</strong> rabatt</p>'),
        'nb',
      ),
      const BenefitHighlight.percent(25),
    );
  });

  test('returns null when there is nothing to claim', () {
    expect(
      benefitHighlightOf(b(title: 'Medlemspriser på arrangementer'), 'nb'),
      isNull,
    );
    expect(benefitHighlightOf(b(title: '100% fornøyd'), 'nb'), isNull);
    expect(benefitHighlightOf(b(title: 'Gratisparkering'), 'nb'), isNull);
    expect(benefitHighlightOf(b(title: 'Siden 2026'), 'nb'), isNull);
  });
}
