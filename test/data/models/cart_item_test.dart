import 'package:biso/data/models/cart_item.dart';
import 'package:biso/data/models/product_custom_field.dart';
import 'package:biso/data/models/product_variation.dart';
import 'package:biso/data/models/webshop_product_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _hoodie = WebshopProduct(
  id: 'prod-1',
  images: ['https://cdn.example/hoodie.png'],
  slug: 'biso-hoodie',
  title: 'BISO Hoodie',
  regularPrice: 399,
  memberPrice: 299,
  stock: 10,
);

const _large = ProductVariation(
  id: 'var-l',
  name: 'Large',
  regularPrice: 449,
  memberPrice: 349,
  stock: 3,
);

const _nameField = ProductCustomField(
  id: 'row-1',
  fieldKey: 'attendee_name',
  label: 'Attendee name',
  type: 'text',
  isRequired: true,
);

void main() {
  group('CartItem.buildLineId', () {
    test('separates the same product in two variations', () {
      expect(
        CartItem.buildLineId(productId: 'p', variationId: 'a'),
        isNot(CartItem.buildLineId(productId: 'p', variationId: 'b')),
      );
    });

    test('separates the same product with different answers', () {
      expect(
        CartItem.buildLineId(
          productId: 'p',
          customFields: const {'name': 'Kari'},
        ),
        isNot(
          CartItem.buildLineId(
            productId: 'p',
            customFields: const {'name': 'Ola'},
          ),
        ),
      );
    });

    test('is stable regardless of the order answers were entered in', () {
      expect(
        CartItem.buildLineId(
          productId: 'p',
          customFields: const {'a': '1', 'b': '2'},
        ),
        CartItem.buildLineId(
          productId: 'p',
          customFields: const {'b': '2', 'a': '1'},
        ),
      );
    });

    test('ignores blank answers, so they do not fork a line', () {
      expect(
        CartItem.buildLineId(
          productId: 'p',
          customFields: const {'a': '1', 'b': '   '},
        ),
        CartItem.buildLineId(productId: 'p', customFields: const {'a': '1'}),
      );
    });
  });

  group('CartItem.fromProduct', () {
    test('prices from the product when no variation is chosen', () {
      final item = CartItem.fromProduct(product: _hoodie);

      expect(item.unitPrice, 399);
      expect(item.memberPrice, 299);
      expect(item.stock, 10);
      expect(item.variationId, isNull);
      expect(item.imageUrl, 'https://cdn.example/hoodie.png');
    });

    test('prices from the variation, which overrides the product', () {
      final item = CartItem.fromProduct(product: _hoodie, variation: _large);

      expect(item.unitPrice, 449);
      expect(item.memberPrice, 349);
      expect(
        item.stock,
        3,
        reason: 'a variation carries its own stock',
      );
      expect(item.variationName, 'Large');
    });

    test('drops blank answers and records the label of the ones it keeps', () {
      final item = CartItem.fromProduct(
        product: _hoodie,
        customFields: const {'attendee_name': ' Kari ', 'unanswered': '  '},
        customFieldDefinitions: const [_nameField],
      );

      expect(item.customFields, {'attendee_name': 'Kari'});
      expect(item.customFieldLabels, {'attendee_name': 'Attendee name'});
    });

    test('falls back to the slug when a product has no translated title', () {
      const untranslated = WebshopProduct(
        id: 'prod-2',
        images: [],
        slug: 'mystery-item',
        regularPrice: 10,
      );
      expect(CartItem.fromProduct(product: untranslated).name, 'mystery-item');
    });
  });

  group('CartItem.checkoutTitle', () {
    test('folds the variation in, because the order line is named from it', () {
      final item = CartItem.fromProduct(product: _hoodie, variation: _large);
      expect(item.checkoutTitle, 'BISO Hoodie — Large');
    });

    test('is just the product name when there is no variation', () {
      expect(CartItem.fromProduct(product: _hoodie).checkoutTitle, 'BISO Hoodie');
    });
  });

  group('CartItem.toCheckoutPayload', () {
    test('never sends a price — the server recomputes every amount', () {
      final payload = CartItem.fromProduct(
        product: _hoodie,
        variation: _large,
        quantity: 2,
      ).toCheckoutPayload();

      expect(payload.containsKey('price'), isFalse);
      expect(payload.containsKey('unitPrice'), isFalse);
      expect(payload.containsKey('unit_price'), isFalse);
      expect(payload, containsPair('productId', 'prod-1'));
      expect(payload, containsPair('quantity', 2));
      expect(payload, containsPair('variationId', 'var-l'));
      expect(payload, containsPair('title', 'BISO Hoodie — Large'));
    });

    test('carries the answers and their labels for the order record', () {
      final payload = CartItem.fromProduct(
        product: _hoodie,
        customFields: const {'attendee_name': 'Kari'},
        customFieldDefinitions: const [_nameField],
      ).toCheckoutPayload();

      expect(payload['customFields'], {'attendee_name': 'Kari'});
      expect(payload['customFieldLabels'], {
        'attendee_name': 'Attendee name',
      });
    });

    test('omits the answer keys entirely when there are none', () {
      final payload = CartItem.fromProduct(product: _hoodie).toCheckoutPayload();
      expect(payload.containsKey('customFields'), isFalse);
      expect(payload.containsKey('customFieldLabels'), isFalse);
    });
  });

  group('CartItem JSON round-trip', () {
    test('survives being persisted and read back', () {
      final original = CartItem.fromProduct(
        product: _hoodie,
        variation: _large,
        quantity: 3,
        customFields: const {'attendee_name': 'Kari'},
        customFieldDefinitions: const [_nameField],
      );

      final restored = CartItem.fromJson(original.toJson());

      expect(restored, original);
    });

    test('recomputes the line id rather than trusting the stored one', () {
      final restored = CartItem.fromJson({
        'lineId': 'stale-key-from-an-older-build',
        'productId': 'prod-1',
        'name': 'BISO Hoodie',
        'unitPrice': 399,
        'quantity': 1,
        'variationId': 'var-l',
        'customFields': {'attendee_name': 'Kari'},
      });

      expect(
        restored.lineId,
        CartItem.buildLineId(
          productId: 'prod-1',
          variationId: 'var-l',
          customFields: const {'attendee_name': 'Kari'},
        ),
      );
    });

    test('tolerates a malformed stored line without throwing', () {
      final restored = CartItem.fromJson(const <String, dynamic>{});
      expect(restored.productId, isEmpty);
      expect(restored.quantity, 1);
    });
  });

  test('lineTotal multiplies the indicative unit price by the quantity', () {
    final item = CartItem.fromProduct(product: _hoodie, quantity: 3);
    expect(item.lineTotal, 1197);
  });
}
