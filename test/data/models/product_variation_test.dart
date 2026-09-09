import 'package:biso/data/models/product_variation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProductVariation.fromMap', () {
    test('parses a real variation row', () {
      final v = ProductVariation.fromMap({
        r'$id': 'wpvar63469',
        'name': 'A year',
        'regular_price': 1500,
        'member_price': 500,
        'stock': 648,
        'sku': null,
        'sort_order': 0,
        'enabled': true,
      });

      expect(v.id, 'wpvar63469');
      expect(v.name, 'A year');
      expect(v.regularPrice, 1500);
      expect(v.memberPrice, 500);
      expect(v.stock, 648);
      expect(v.sku, isNull);
      expect(v.sortOrder, 0);
      expect(v.enabled, isTrue);
    });

    test('tolerates a variation with no prices or stock', () {
      final v = ProductVariation.fromMap({
        r'$id': 'wpvar1',
        'name': '3 Years Fall 2026 / Bergen',
        'regular_price': 1350,
        'member_price': null,
        'stock': null,
      });

      expect(v.memberPrice, isNull);
      expect(v.stock, isNull);
      expect(v.sortOrder, 0, reason: 'sort_order defaults to 0');
      expect(v.enabled, isTrue, reason: 'enabled defaults to true');
    });
  });

  group('ProductVariation.listFrom', () {
    test('returns empty for null or a non-list', () {
      expect(ProductVariation.listFrom(null), isEmpty);
      expect(ProductVariation.listFrom('nope'), isEmpty);
    });

    test('drops disabled variations and sorts by sort_order', () {
      final list = ProductVariation.listFrom([
        {r'$id': 'c', 'name': 'Third', 'sort_order': 2, 'enabled': true},
        {r'$id': 'x', 'name': 'Hidden', 'sort_order': 1, 'enabled': false},
        {r'$id': 'a', 'name': 'First', 'sort_order': 0, 'enabled': true},
      ]);

      expect(list.map((v) => v.name), ['First', 'Third']);
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
            'name': 'Tied $i',
            'sort_order': 0,
            'enabled': true,
          },
        );

        final list = ProductVariation.listFrom(input);

        expect(
          list.map((v) => v.name).toList(),
          List<String>.generate(count, (i) => 'Tied $i'),
        );
      },
    );

    test(
      'breaks ties by source order while keeping overall ascending order',
      () {
        // Interleave a large block of entries tied at sort_order 5 with
        // entries at distinct sort_order values (1, 2, 8, 9), scattered
        // among the tied block rather than only at the edges. This proves
        // two things at once: ties resolve to source order, and the
        // distinct-valued entries still land in correct ascending position.
        const tieCount = 40;
        final input = <Map<String, dynamic>>[
          {r'$id': 'high-b', 'name': 'High-B', 'sort_order': 9, 'enabled': true},
        ];
        for (var i = 0; i < tieCount; i++) {
          input.add({
            r'$id': 'tied-$i',
            'name': 'Tied $i',
            'sort_order': 5,
            'enabled': true,
          });
          if (i == 0) {
            input.add({
              r'$id': 'low-a',
              'name': 'Low-A',
              'sort_order': 1,
              'enabled': true,
            });
          }
          if (i == 1) {
            input.add({
              r'$id': 'high-a',
              'name': 'High-A',
              'sort_order': 8,
              'enabled': true,
            });
          }
          if (i == 2) {
            input.add({
              r'$id': 'low-b',
              'name': 'Low-B',
              'sort_order': 2,
              'enabled': true,
            });
          }
        }

        final list = ProductVariation.listFrom(input);

        final expected = [
          'Low-A',
          'Low-B',
          ...List<String>.generate(tieCount, (i) => 'Tied $i'),
          'High-A',
          'High-B',
        ];

        expect(list.map((v) => v.name).toList(), expected);
      },
    );
  });
}
