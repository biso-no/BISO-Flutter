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

const _firstRequiredField = ProductCustomField(
  id: 'passport',
  fieldKey: 'passport_number',
  label: 'Passport number',
  type: 'text',
  isRequired: true,
);

/// The required field is *first* here (unlike [_product], where it's last),
/// with several trailing optional fields after it. Scrolling down and then
/// triggering `_revealCustomField` exercises the "already built" branch —
/// the field has already been laid out, so revealing it means scrolling
/// *up*, landing its top at the scroll content's `y = 0`, i.e. straight
/// behind the translucent header unless `_clearHeaderAbove` corrects it.
/// [_product]'s below-the-fold case instead hits the "never built" branch,
/// which scrolls to `maxScrollExtent` — since the required field there is
/// also the *last* section of the page, that already lands it near the
/// natural bottom of the content, well clear of the header with or without
/// the nudge, so it never actually exercises `_clearHeaderAbove`.
WebshopProduct _productWithLeadingRequiredField() => WebshopProduct(
  id: 'p2',
  images: const [],
  title: 'BISO Hoodie',
  regularPrice: 349,
  customFields: [
    _firstRequiredField,
    for (var i = 0; i < 10; i++)
      ProductCustomField(
        id: 'trailing$i',
        fieldKey: 'trailing_$i',
        label: 'Trailing field $i',
        type: 'text',
      ),
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

  testWidgets(
    'a required field placed first, scrolled above the viewport, is '
    'revealed below the translucent header rather than behind it, and its '
    'validation error paints below its own label (exercises '
    '_clearHeaderAbove directly — the case above never scrolls the field '
    'behind the header even without it, since it is also the last section '
    'of the page)',
    (tester) async {
      await pumpBisoScreen(
        tester,
        WebshopProductDetailScreen(product: _productWithLeadingRequiredField()),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      // Scroll down far enough that the required field (first in the
      // custom-fields section, right after the 360pt gallery and the
      // title/price block) is now scrolled up past the top edge — still
      // built and registered with the Form (it was on screen a moment
      // ago), but needing an *upward* scroll to reveal it again. This is
      // the "already built" branch of `_revealCustomField`.
      await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(find.text('Passport number *'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Add to cart'));
      await tester.pumpAndSettle();

      final labelFinder = find.text('Passport number *');
      expect(labelFinder, findsOneWidget);
      final labelRect = tester.getRect(labelFinder);
      expect(labelRect.top, greaterThanOrEqualTo(47 + kBisoHeaderHeight));

      final errorFinder = find.text('This field is required');
      expect(errorFinder, findsOneWidget);
      final errorRect = tester.getRect(errorFinder);
      expect(errorRect.top, greaterThan(labelRect.bottom));
    },
  );

  testWidgets(
    'focusing the lowest custom field with the keyboard open keeps it '
    'clear of the floating purchase bar',
    (tester) async {
      await pumpBisoScreen(
        tester,
        WebshopProductDetailScreen(product: _product()),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      // Scroll the last (lowest) custom field into view and focus it.
      await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
      final field = find.byType(TextFormField).last;
      expect(field, findsOneWidget);
      await tester.tap(field);
      await tester.pump();

      // Open a 336pt keyboard, in physical pixels at this view's device
      // pixel ratio (set by pumpBisoScreen), the same way flutter_test
      // simulates the IME appearing: MediaQuery.viewInsets changes, which
      // EditableText reacts to by scrolling its own caret into view using
      // its `scrollPadding`.
      final dpr = tester.view.devicePixelRatio;
      tester.view.viewInsets = FakeViewPadding(bottom: 336 * dpr);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      final fieldBottom = tester.getBottomLeft(field).dy;
      final barTop = tester.getTopLeft(find.byType(BisoBottomBar)).dy;
      expect(fieldBottom, lessThanOrEqualTo(barTop));
    },
  );
}
