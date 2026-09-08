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
  });
}
