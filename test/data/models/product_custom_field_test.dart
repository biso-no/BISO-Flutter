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

    test(
      'preserves source order for many entries sharing the same sort_order',
      () {
        // sort_order defaults to 0 in the Appwrite schema, so entries
        // created without explicit ordering tie immediately. List.sort is
        // documented as unstable, so this fixture must be large enough that
        // an unstable sort would realistically reorder it (a two-entry tie
        // can pass by luck) — 40 tied entries is well past the size where
        // Dart's sort switches away from its stable small-list path.
        const count = 40;
        final input = List<Map<String, dynamic>>.generate(
          count,
          (i) => {
            r'$id': 'tied-$i',
            'field_key': 'tied-$i',
            'label': 'Tied $i',
            'type': 'text',
            'sort_order': 0,
            'enabled': true,
          },
        );

        final list = ProductCustomField.listFrom(input);

        expect(
          list.map((f) => f.label).toList(),
          List<String>.generate(count, (i) => 'Tied $i'),
        );
      },
    );

    test(
      'breaks ties by source order while keeping overall ascending order',
      () {
        // Interleave a large block of fields tied at sort_order 5 with
        // fields at distinct sort_order values (1, 2, 8, 9), scattered
        // among the tied block rather than only at the edges. This proves
        // two things at once: ties resolve to source order, and the
        // distinct-valued fields still land in correct ascending position.
        const tieCount = 40;
        final input = <Map<String, dynamic>>[
          {
            r'$id': 'high-b',
            'field_key': 'high-b',
            'label': 'High-B',
            'type': 'text',
            'sort_order': 9,
            'enabled': true,
          },
        ];
        for (var i = 0; i < tieCount; i++) {
          input.add({
            r'$id': 'tied-$i',
            'field_key': 'tied-$i',
            'label': 'Tied $i',
            'type': 'text',
            'sort_order': 5,
            'enabled': true,
          });
          if (i == 0) {
            input.add({
              r'$id': 'low-a',
              'field_key': 'low-a',
              'label': 'Low-A',
              'type': 'text',
              'sort_order': 1,
              'enabled': true,
            });
          }
          if (i == 1) {
            input.add({
              r'$id': 'high-a',
              'field_key': 'high-a',
              'label': 'High-A',
              'type': 'text',
              'sort_order': 8,
              'enabled': true,
            });
          }
          if (i == 2) {
            input.add({
              r'$id': 'low-b',
              'field_key': 'low-b',
              'label': 'Low-B',
              'type': 'text',
              'sort_order': 2,
              'enabled': true,
            });
          }
        }

        final list = ProductCustomField.listFrom(input);

        final expected = [
          'Low-A',
          'Low-B',
          ...List<String>.generate(tieCount, (i) => 'Tied $i'),
          'High-A',
          'High-B',
        ];

        expect(list.map((f) => f.label).toList(), expected);
      },
    );
  });
}
