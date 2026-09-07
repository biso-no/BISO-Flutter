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
  });
}
