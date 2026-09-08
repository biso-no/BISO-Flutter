import 'package:biso/data/models/webshop_product_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> get realProductRow => {
  r'$id': 'wpprod61050',
  'slug': 'co-payment-biso-sweater-trondheim-2025',
  'status': 'published',
  'campus_id': '3',
  'departmentId': '11',
  'regular_price': 0,
  'member_price': null,
  'member_only': false,
  'category': null,
  'image': '6a99004100362c968d1e',
  'images': ['6a99004100362c968d1e'],
  'stock': null,
  'tags': <String>[],
  'inventory_mode': 'unlimited',
  'linked_event_id': null,
  'translation_refs': [
    {
      'locale': 'no',
      'title': 'Egenandel – BISO-genser Trondheim 2025',
      'description': '<p>Genser.</p>',
      'short_description': 'Genser.',
      'content_type': 'product',
    },
    {
      'locale': 'en',
      'title': 'Co-payment – BISO sweater Trondheim 2025',
      'description': '<p>Sweater.</p>',
      'short_description': 'Sweater.',
      'content_type': 'product',
    },
  ],
  'variations': <Map<String, dynamic>>[],
  'custom_fields': [
    {r'$id': 'c3', 'field_key': 'c3', 'label': 'Størrelse', 'type': 'text', 'is_required': true, 'sort_order': 2, 'enabled': true},
    {r'$id': 'c1', 'field_key': 'c1', 'label': 'Fullt navn', 'type': 'text', 'is_required': true, 'sort_order': 0, 'enabled': true},
    {r'$id': 'c2', 'field_key': 'c2', 'label': 'Stillingstittel og utvalg', 'type': 'text', 'is_required': true, 'sort_order': 1, 'enabled': true},
  ],
};

void main() {
  group('WebshopProduct.fromAppwriteRow', () {
    test('parses scalar columns from a real row', () {
      final p = WebshopProduct.fromAppwriteRow(realProductRow);

      expect(p.id, 'wpprod61050');
      expect(p.slug, 'co-payment-biso-sweater-trondheim-2025');
      expect(p.campusId, '3');
      expect(p.regularPrice, 0);
      expect(p.memberPrice, isNull);
      expect(p.memberOnly, isFalse);
      expect(p.inventoryMode, 'unlimited');
      expect(p.stock, isNull);
    });

    test('resolves title and description for the requested locale', () {
      expect(
        WebshopProduct.fromAppwriteRow(realProductRow, locale: 'en').title,
        'Co-payment – BISO sweater Trondheim 2025',
      );
      expect(
        WebshopProduct.fromAppwriteRow(realProductRow, locale: 'no').title,
        'Egenandel – BISO-genser Trondheim 2025',
      );
    });

    test('normalizes a bare image file id into a URL', () {
      final p = WebshopProduct.fromAppwriteRow(realProductRow);
      expect(
        p.images.single,
        contains('/storage/buckets/media/files/6a99004100362c968d1e/view'),
      );
    });

    test('keeps an already-complete image URL intact', () {
      const url =
          'https://appwrite.biso.no/v1/storage/buckets/media/files/abc/view?project=biso';
      final p = WebshopProduct.fromAppwriteRow({
        ...realProductRow,
        'images': [url],
      });
      expect(p.images.single, url);
    });

    test('orders custom fields by sort_order regardless of payload order', () {
      final p = WebshopProduct.fromAppwriteRow(realProductRow);
      expect(
        p.customFields.map((f) => f.label),
        ['Fullt navn', 'Stillingstittel og utvalg', 'Størrelse'],
      );
    });

    test('parses variations when present', () {
      final p = WebshopProduct.fromAppwriteRow({
        ...realProductRow,
        'variations': [
          {r'$id': 'v2', 'name': 'Semester', 'regular_price': 750, 'member_price': 250, 'sort_order': 1, 'enabled': true},
          {r'$id': 'v1', 'name': 'A year', 'regular_price': 1500, 'member_price': 500, 'sort_order': 0, 'enabled': true},
        ],
      });

      expect(p.variations.map((v) => v.name), ['A year', 'Semester']);
      expect(p.variations.first.memberPrice, 500);
    });

    test('tolerates a row with no translations, variations or custom fields', () {
      final row = {...realProductRow}
        ..remove('translation_refs')
        ..remove('variations')
        ..remove('custom_fields');
      final p = WebshopProduct.fromAppwriteRow(row);

      expect(p.title, '');
      expect(p.variations, isEmpty);
      expect(p.customFields, isEmpty);
    });

    test('two products differing only in variations are not equal', () {
      final a = WebshopProduct.fromAppwriteRow(realProductRow);
      final b = WebshopProduct.fromAppwriteRow({
        ...realProductRow,
        'variations': [
          {r'$id': 'v1', 'name': 'A year', 'sort_order': 0, 'enabled': true},
        ],
      });
      expect(a, isNot(equals(b)));
    });
  });
}
