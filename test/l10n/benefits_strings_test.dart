import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final no = lookupAppLocalizations(const Locale('no'));

  test('count in campus pluralises in both languages', () {
    expect(no.benefitsCountInCampus(1, 'Oslo'), '1 fordel i Oslo');
    expect(no.benefitsCountInCampus(27, 'Oslo'), '27 fordeler i Oslo');
    expect(en.benefitsCountInCampus(1, 'Oslo'), '1 benefit in Oslo');
    expect(en.benefitsCountInCampus(27, 'Oslo'), '27 benefits in Oslo');
  });

  test('locked body pluralises and never says 0 other benefits', () {
    expect(
      no.benefitsLockedBody(26, 'Trondheim'),
      'Bli medlem for å bruke dette tilbudet og 26 andre fordeler i '
      'Trondheim.',
    );
    expect(
      no.benefitsLockedBody(1, 'Oslo'),
      'Bli medlem for å bruke dette tilbudet og 1 annen fordel i Oslo.',
    );
    expect(
      en.benefitsLockedBody(1, 'Oslo'),
      'Join to use this deal and 1 other benefit in Oslo.',
    );
    expect(
      en.benefitsLockedBody(26, 'Oslo'),
      'Join to use this deal and 26 other benefits in Oslo.',
    );
    expect(
      no.benefitsLockedBody(0, 'Oslo'),
      'Bli medlem for å bruke dette tilbudet.',
    );
    expect(en.benefitsLockedBody(0, 'Oslo'), 'Join to use this deal.');
  });

  test('top card strings pluralise', () {
    expect(
      no.benefitsTopNonMember(1, 'Oslo'),
      'fordel venter på deg som BISO-medlem i Oslo',
    );
    expect(
      no.benefitsTopNonMember(5, 'Oslo'),
      'fordeler venter på deg som BISO-medlem i Oslo',
    );
    expect(
      en.benefitsTopNonMember(5, 'Oslo'),
      'benefits are waiting for you as a BISO member in Oslo',
    );
    expect(no.benefitsTopMember(1, 'Oslo'), 'fordel er din i Oslo');
    expect(no.benefitsTopMember(5, 'Oslo'), 'fordeler er dine i Oslo');
    expect(en.benefitsTopMember(1, 'Oslo'), 'benefit is yours in Oslo');
    expect(en.benefitsTopMember(5, 'Oslo'), 'benefits are yours in Oslo');
    expect(
      no.benefitsTopNeutral(1, 'Oslo'),
      'fordel for BISO-medlemmer i Oslo',
    );
    expect(
      en.benefitsTopNeutral(5, 'Oslo'),
      'benefits for BISO members in Oslo',
    );
  });

  test('simple and dated strings exist in both languages', () {
    expect(no.benefitsReasonEnds('30. nov.'), 'Slutter 30. nov.');
    expect(en.benefitsReasonEnds('30 Nov'), 'Ends 30 Nov');
    expect(no.benefitsScreenTitle, 'Fordeler');
    expect(en.benefitsScreenTitle, 'Benefits');
    expect(no.benefitsCategoryFoodDrink, 'Mat og drikke');
    expect(en.benefitsCategoryOther, 'Other');
    expect(no.benefitsSectionSafety, 'Trygghet og støtte');
    expect(en.benefitsMoreLogos(3), '+ 3 more');
    expect(no.benefitsMoreInCategory('Reise'), 'Mer innen Reise');
    expect(no.benefitsMoreDeals, 'Flere tilbud');
    expect(en.benefitsMoreDeals, 'More deals');
    expect(
      no.benefitsLockedSignedOutBody,
      'Logg inn for å bruke tilbudet som medlem.',
    );
    expect(
      en.benefitsLockedSignedOutBody,
      'Sign in to use this deal as a member.',
    );
    expect(en.benefitsUntilFurther, 'Until further notice');
  });
}
