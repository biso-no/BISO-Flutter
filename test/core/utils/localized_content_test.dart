import 'package:biso/core/utils/localized_content.dart';
import 'package:biso/data/models/content_translation.dart';
import 'package:flutter_test/flutter_test.dart';

ContentTranslation t(String locale, String title) => ContentTranslation(
  locale: locale,
  title: title,
  description: '<p>$title</p>',
  shortDescription: title,
);

void main() {
  group('resolveLocalizedContent', () {
    final both = [t('no', 'Karrieredagene'), t('en', 'Career Days')];

    test('returns the requested locale when present', () {
      expect(resolveLocalizedContent(both, 'en').title, 'Career Days');
      expect(resolveLocalizedContent(both, 'no').title, 'Karrieredagene');
    });

    test('falls back to Norwegian when the requested locale is missing', () {
      expect(resolveLocalizedContent(both, 'de').title, 'Karrieredagene');
    });

    test('falls back to English when Norwegian is absent', () {
      final onlyEn = [t('en', 'Career Days')];
      expect(resolveLocalizedContent(onlyEn, 'no').title, 'Career Days');
    });

    test('falls back to the first available for an unexpected locale', () {
      final odd = [t('fr', 'Journees')];
      expect(resolveLocalizedContent(odd, 'no').title, 'Journees');
    });

    test('returns empty content rather than throwing when list is empty', () {
      final r = resolveLocalizedContent(const [], 'no');
      expect(r.title, '');
      expect(r.description, '');
      expect(r.shortDescription, isNull);
    });

    test(
      'skips a blank title in the requested locale in favour of another '
      'locale with a real title',
      () {
        final mixed = [t('en', ''), t('no', 'Noe')];
        expect(resolveLocalizedContent(mixed, 'en').title, 'Noe');
      },
    );

    test(
      'the first-available tier skips a blank-title entry for a later '
      'non-blank one',
      () {
        final mixed = [t('fr', ''), t('de', 'Etwas')];
        expect(resolveLocalizedContent(mixed, 'no').title, 'Etwas');
      },
    );

    test('treats a whitespace-only title as blank', () {
      final mixed = [t('en', '   '), t('no', 'Noe')];
      expect(resolveLocalizedContent(mixed, 'en').title, 'Noe');
    });

    test(
      'returns blank content without throwing when all titles are blank',
      () {
        final allBlank = [t('en', ''), t('no', '   ')];
        final r = resolveLocalizedContent(allBlank, 'en');
        expect(r.title, '');
      },
    );
  });
}
