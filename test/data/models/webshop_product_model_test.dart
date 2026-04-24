import 'package:biso/data/models/webshop_product_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WebshopProduct parses WooCommerce ACF metadata', () {
    final product = WebshopProduct.fromFunctionMap({
      'id': 65835,
      'name': 'Gabi Langaas',
      'permalink': 'https://biso.no/product/gabi-langaas/',
      'price': '1287.40',
      'sale_price': '',
      'images': [
        {'src': 'https://example.com/image.jpg'},
      ],
      'meta_data': [
        {'key': 'campus', 'value': '1'},
        {'key': '_campus', 'value': 'field_66a3ba7e42ec0'},
        {'key': 'department_oslo', 'value': '21'},
        {'key': '_department_oslo', 'value': 'field_66a3baa9a364d'},
      ],
    });

    expect(product.id, 65835);
    expect(product.campusId, '1');
    expect(product.campusLabel, 'Oslo');
    expect(product.departmentId, '21');
    expect(product.images, ['https://example.com/image.jpg']);
    expect(product.url, 'https://biso.no/product/gabi-langaas/');
  });
}
