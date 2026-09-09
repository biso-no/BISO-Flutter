import 'package:biso/data/models/content_translation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ContentTranslation.fromMap', () {
    test('parses a real content_translations row', () {
      final t = ContentTranslation.fromMap({
        'content_id': 'wpprod37313',
        'locale': 'en',
        'title': 'Booklocker - Campus Oslo',
        'description': '<p>Pick a locker.</p>',
        'short_description': 'Pick a locker.',
        'additional_fields': null,
        'content_type': 'product',
      });

      expect(t.locale, 'en');
      expect(t.title, 'Booklocker - Campus Oslo');
      expect(t.description, '<p>Pick a locker.</p>');
      expect(t.shortDescription, 'Pick a locker.');
      expect(t.contentType, 'product');
      expect(t.contentId, 'wpprod37313');
      expect(t.additionalFields, isNull);
    });

    test('defaults missing strings to empty rather than throwing', () {
      final t = ContentTranslation.fromMap({'locale': 'no'});

      expect(t.locale, 'no');
      expect(t.title, '');
      expect(t.description, '');
      expect(t.shortDescription, isNull);
    });
  });
}
