import 'package:biso/data/models/product_custom_field.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProductCustomField.fromMap', () {
    test('parses a real required field row', () {
      final f = ProductCustomField.fromMap({
        r'$id': '690241300bac3',
        'field_key': '690241300bac3',
        'label': 'Fullt navn',
        'type': 'text',
        'is_required': true,
        'placeholder': null,
        'help_text': null,
        'options': <String>[],
        'sort_order': 0,
        'enabled': true,
      });

      expect(f.id, '690241300bac3');
      expect(f.label, 'Fullt navn');
      expect(f.type, 'text');
      expect(f.isRequired, isTrue);
      expect(f.options, isEmpty);
      expect(f.sortOrder, 0);
    });

    test('defaults is_required to false and enabled to true', () {
      final f = ProductCustomField.fromMap({
        r'$id': 'f1',
        'field_key': 'f1',
        'label': 'Kjønn',
        'type': 'text',
      });

      expect(f.isRequired, isFalse);
      expect(f.enabled, isTrue);
    });

    test('parses select options when present', () {
      final f = ProductCustomField.fromMap({
        r'$id': 'f2',
        'field_key': 'f2',
        'label': 'Størrelse',
        'type': 'select',
        'options': ['S', 'M', 'L'],
      });

      expect(f.options, ['S', 'M', 'L']);
    });
  });

  group('ProductCustomField.listFrom', () {
    test('returns empty for null or a non-list', () {
      expect(ProductCustomField.listFrom(null), isEmpty);
      expect(ProductCustomField.listFrom(42), isEmpty);
    });

    test('drops disabled fields and sorts by sort_order', () {
      final list = ProductCustomField.listFrom([
        {r'$id': 'b', 'field_key': 'b', 'label': 'Second', 'type': 'text', 'sort_order': 1, 'enabled': true},
        {r'$id': 'z', 'field_key': 'z', 'label': 'Gone', 'type': 'text', 'sort_order': 0, 'enabled': false},
        {r'$id': 'a', 'field_key': 'a', 'label': 'First', 'type': 'text', 'sort_order': 0, 'enabled': true},
      ]);

      expect(list.map((f) => f.label), ['First', 'Second']);
    });
  });
}
