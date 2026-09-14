import 'package:biso/data/models/product_custom_field.dart';
import 'package:biso/data/models/product_variation.dart';
import 'package:biso/data/models/webshop_product_model.dart';
import 'package:biso/presentation/screens/explore/webshop_product_detail_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/shop/cart_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/biso_screen_harness.dart';

const _requiredField = ProductCustomField(
  id: 'shirt',
  fieldKey: 'shirt_size',
  label: 'Shirt size',
  type: 'text',
  isRequired: true,
);

WebshopProduct _product() => WebshopProduct(
  id: 'p1',
  images: const [
    'https://example.com/a.png',
    'https://example.com/b.png',
  ],
  title: 'BISO Hoodie',
  description:
      'A cosy hoodie in BI blue, with the BISO logo on the chest and a '
      'roomy front pocket. Machine washable at 30 degrees. '
      'A cosy hoodie in BI blue, with the BISO logo on the chest and a '
      'roomy front pocket. Machine washable at 30 degrees.',
  regularPrice: 349,
  variations: const [
    ProductVariation(id: 'v1', name: 'Small', regularPrice: 349),
    ProductVariation(
      id: 'v2',
      name: 'Large',
      regularPrice: 399,
      memberPrice: 349,
    ),
  ],
  customFields: [
    for (var i = 0; i < 8; i++)
      ProductCustomField(
        id: 'filler$i',
        fieldKey: 'filler_$i',
        label: 'Filler field $i',
        type: 'text',
      ),
    _requiredField,
  ],
);

List<Override> _overrides() => [
  cartUserIdProvider.overrideWithValue(null),
  hasValidMembershipProvider.overrideWithValue(false),
];

void main() {
  setUp(() {
    // The cart persists to SharedPreferences; give it an in-memory store so
    // the screen's cart badge builds without a platform channel.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'Webshop product detail builds on BisoPage in every appearance',
    (tester) async {
      await expectBuildsCleanly(
        tester,
        () => WebshopProductDetailScreen(product: _product()),
        overrides: _overrides(),
      );
    },
  );

  testWidgets(
    'a required custom field below the fold shows its validation message '
    'when the purchase button is tapped, and the scroll clears the '
    'translucent header instead of hiding the field behind it',
    (tester) async {
      await pumpBisoScreen(
        tester,
        WebshopProductDetailScreen(product: _product()),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      // Sanity check: the field truly starts off the bottom of this
      // viewport, so revealing it is exercising a real scroll rather than
      // trivially passing because it was on-screen already.
      expect(find.text('Shirt size *'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Add to cart'));
      await tester.pumpAndSettle();

      expect(find.text('This field is required'), findsWidgets);

      final fieldTop = tester.getTopLeft(find.text('Shirt size *')).dy;
      expect(fieldTop, greaterThanOrEqualTo(47 + kBisoHeaderHeight));
    },
  );
}
