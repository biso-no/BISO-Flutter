import 'dart:convert';

import 'package:biso/data/models/cart_item.dart';
import 'package:biso/data/models/product_custom_field.dart';
import 'package:biso/data/models/webshop_product_model.dart';
import 'package:biso/presentation/screens/explore/webshop_product_detail_screen.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/data/services/shop_api_client.dart';
import 'package:biso/providers/shop/cart_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Review finding 1: required-field validation on the webshop product
/// detail screen must block even when the offending field lies below the
/// fold of a lazily-built `SliverList` and has therefore never registered
/// with the enclosing `Form`. `Form.validate()` alone cannot catch this
/// (it only iterates *registered* fields), so `_handleAddToCart` also checks
/// [firstMissingRequiredCustomField] directly against the screen's
/// collected controller/select state, independent of what has been built.
///
/// `firstMissingRequiredCustomField` is a plain, `@visibleForTesting`
/// top-level function with no widget/BuildContext dependency, so its exact
/// gating logic is covered here with plain unit tests. Reproducing the full
/// "never built" scenario end-to-end additionally needs a real widget tree
/// (a `SliverList` only skips building genuinely off-screen children), so a
/// small number of widget tests below drive the actual screen with a
/// shrunk viewport to force that condition, and assert on the resulting
/// `_handleAddToCart` behavior (which is otherwise private and not
/// independently callable without building the screen).
void main() {
  group('firstMissingRequiredCustomField', () {
    const requiredText = ProductCustomField(
      id: '1',
      fieldKey: 'full_name',
      label: 'Full name',
      type: 'text',
      isRequired: true,
    );
    const requiredSelect = ProductCustomField(
      id: '2',
      fieldKey: 'size',
      label: 'Size',
      type: 'select',
      isRequired: true,
      options: ['S', 'M', 'L'],
    );
    const optionalText = ProductCustomField(
      id: '3',
      fieldKey: 'notes',
      label: 'Notes',
      type: 'text',
    );

    test('returns null when there are no custom fields', () {
      expect(
        firstMissingRequiredCustomField(
          customFields: const [],
          selectValues: const {},
          textValues: const {},
        ),
        isNull,
      );
    });

    test('returns null once every required field has a value', () {
      expect(
        firstMissingRequiredCustomField(
          customFields: const [requiredText, requiredSelect, optionalText],
          selectValues: const {'size': 'M'},
          textValues: const {'full_name': 'Kari Nordmann'},
        ),
        isNull,
      );
    });

    test('ignores an optional field left entirely blank', () {
      expect(
        firstMissingRequiredCustomField(
          customFields: const [requiredText, optionalText],
          selectValues: const {},
          textValues: const {'full_name': 'Kari Nordmann', 'notes': ''},
        ),
        isNull,
      );
    });

    test(
      'blocks on a required text field whose entry is missing from the map '
      'entirely (never built) — this is Finding 1: the function takes no '
      'Form/BuildContext, so it cannot depend on the field ever having '
      'registered with one',
      () {
        final result = firstMissingRequiredCustomField(
          customFields: const [requiredText],
          selectValues: const {},
          textValues: const {},
        );
        expect(result, same(requiredText));
      },
    );

    test('blocks on a required text field that is an empty string', () {
      final result = firstMissingRequiredCustomField(
        customFields: const [requiredText],
        selectValues: const {},
        textValues: const {'full_name': ''},
      );
      expect(result, same(requiredText));
    });

    test('blocks on a required text field that is whitespace only', () {
      final result = firstMissingRequiredCustomField(
        customFields: const [requiredText],
        selectValues: const {},
        textValues: const {'full_name': '   '},
      );
      expect(result, same(requiredText));
    });

    test('blocks on a required select field with no selection', () {
      final result = firstMissingRequiredCustomField(
        customFields: const [requiredSelect],
        selectValues: const {'size': null},
        textValues: const {},
      );
      expect(result, same(requiredSelect));
    });

    test('blocks on a required select field missing from the map entirely', () {
      final result = firstMissingRequiredCustomField(
        customFields: const [requiredSelect],
        selectValues: const {},
        textValues: const {},
      );
      expect(result, same(requiredSelect));
    });

    test('returns fields in customFields order, not map order', () {
      const second = ProductCustomField(
        id: '4',
        fieldKey: 'second',
        label: 'Second field',
        type: 'text',
        isRequired: true,
      );
      // 'second' is filled in but the first-declared field ('full_name')
      // has no entry at all — the first missing field in *list* order must
      // win, regardless of what order the maps happen to iterate in.
      final result = firstMissingRequiredCustomField(
        customFields: const [requiredText, second],
        selectValues: const {},
        textValues: const {'second': 'filled'},
      );
      expect(result, same(requiredText));
    });
  });

  group('WebshopProductDetailScreen add-to-cart button (widget)', () {
    setUp(() {
      // The cart persists to SharedPreferences; give it an in-memory store so
      // the screen's cart badge builds without a platform channel.
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    Future<void> pumpScreen(
      WidgetTester tester,
      WebshopProduct product, {
      String? userId,
      ShopApiClient? api,
      bool isMember = false,
    }) {
      return tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Pin the identity rather than standing up the whole
            // authentication stack (which would try to reach Appwrite).
            cartUserIdProvider.overrideWithValue(userId),
            hasValidMembershipProvider.overrideWithValue(isMember),
            if (api != null) shopApiClientProvider.overrideWithValue(api),
          ],
          child: MaterialApp(
            home: WebshopProductDetailScreen(product: product),
          ),
        ),
      );
    }

    testWidgets(
      'blocks the add and never puts anything in the cart when a '
      'required field below the fold is blank, without the user scrolling '
      'first',
      (tester) async {
        addTearDown(() => tester.view.resetPhysicalSize());
        // A small viewport (well under the sliver's default 250px cache
        // extent once the fixed header content above the fields is
        // accounted for) so the last required field is genuinely never
        // built until the fix's own scroll logic reaches it — reproducing
        // Finding 1 rather than merely asserting the pure function again.
        tester.view.physicalSize = const Size(400, 500);
        tester.view.devicePixelRatio = 1.0;

        final filler = List.generate(
          6,
          (i) => ProductCustomField(
            id: 'filler$i',
            fieldKey: 'filler_$i',
            label: 'Filler field $i',
            type: 'text',
          ),
        );
        const belowFold = ProductCustomField(
          id: 'shirt',
          fieldKey: 'shirt_size',
          label: 'Shirt size',
          type: 'text',
          isRequired: true,
        );

        final product = WebshopProduct(
          id: 'p1',
          images: const [],
          title: 'Test Product',
          regularPrice: 100,
          customFields: [...filler, belowFold],
        );

        await pumpScreen(tester, product);
        await tester.pumpAndSettle();

        // Sanity check that the premise holds: the required field's label
        // is not yet rendered anywhere before Continue is tapped — it has
        // genuinely never been built.
        expect(find.textContaining('Shirt size'), findsNothing);

        await tester.tap(find.widgetWithText(FilledButton, 'Add to cart'));
        await tester.pumpAndSettle();

        // The bug: Form.validate() reports true for an unregistered field,
        // so the old code fell straight through past the gate. Nothing may
        // reach the cart.
        expect(find.textContaining('added to your cart'), findsNothing);

        // A clear message naming the *label* (never the fieldKey) is shown,
        // and the fix's scroll logic has brought the field itself into the
        // tree (its label now renders too) and re-validated it, so its own
        // inline error text is visible as well.
        expect(find.textContaining('Shirt size'), findsWidgets);
        expect(find.textContaining('shirt_size'), findsNothing);
        expect(find.text('This field is required'), findsWidgets);
      },
    );

    testWidgets(
      'does not paint validation errors on untouched fields just because '
      'a different field changed (Finding 2)',
      (tester) async {
        const field1 = ProductCustomField(
          id: '1',
          fieldKey: 'f1',
          label: 'Field One',
          type: 'text',
          isRequired: true,
        );
        const field2 = ProductCustomField(
          id: '2',
          fieldKey: 'f2',
          label: 'Field Two',
          type: 'text',
          isRequired: true,
        );
        const field3 = ProductCustomField(
          id: '3',
          fieldKey: 'f3',
          label: 'Field Three',
          type: 'text',
          isRequired: true,
        );

        final product = WebshopProduct(
          id: 'p2',
          images: const [],
          title: 'Another product',
          regularPrice: 50,
          customFields: const [field1, field2, field3],
        );

        await pumpScreen(tester, product);
        await tester.pumpAndSettle();

        // All three fields are on screen (no Continue tap has happened
        // yet). Typing into the first field alone must not paint errors
        // under fields 2 and 3.
        await tester.enterText(find.byType(TextFormField).first, 'a');
        await tester.pump();

        expect(find.text('This field is required'), findsNothing);
      },
    );

    testWidgets(
      'offers a product with no custom fields for purchase — every published '
      'product is buyable, not only those carrying a form',
      (tester) async {
        final product = WebshopProduct(
          id: 'p3',
          images: const [],
          title: 'Plain product',
          regularPrice: 20,
        );

        await pumpScreen(tester, product);
        await tester.pumpAndSettle();

        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Add to cart'),
        );
        expect(button.onPressed, isNotNull);
      },
    );

    testWidgets('refuses to add a sold-out product', (tester) async {
      final product = WebshopProduct(
        id: 'p4',
        images: const [],
        title: 'Gone product',
        regularPrice: 20,
        stock: 0,
      );

      await pumpScreen(tester, product);
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Sold out'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'reports the reason instead of claiming an item was added when the '
      'stock hold is rejected',
      (tester) async {
        final product = WebshopProduct(
          id: 'p6',
          images: const [],
          title: 'Last one',
          regularPrice: 20,
        );

        await pumpScreen(
          tester,
          product,
          userId: 'buyer-1',
          api: _RejectingShopApi(),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(FilledButton, 'Add to cart'));
        await tester.pumpAndSettle();

        // The hold is written during the add and a 409 removes the line again
        // rather than throwing, so a bare "added" message would be a lie.
        expect(find.textContaining('added to your cart'), findsNothing);
        expect(find.text('Sold out while you were deciding'), findsOneWidget);
      },
    );

    testWidgets(
      'does not claim success when the clamp gave the requested units to a '
      'line that was already in the cart',
      (tester) async {
        final product = WebshopProduct(
          id: 'p7',
          images: const [],
          title: 'Scarce product',
          regularPrice: 20,
        );

        // Two of this product are already in the cart, and the server can hold
        // no more than that. The add merges into the existing line, the clamp
        // puts it straight back, and nothing was actually added — yet the
        // product is still in the cart, which is why the cart cannot be used
        // to judge the outcome.
        final seeded = CartItem.fromProduct(product: product, quantity: 2);
        SharedPreferences.setMockInitialValues(<String, Object>{
          'shop_cart_v1': jsonEncode([seeded.toJson()]),
          'shop_cart_v1_user': 'buyer-1',
        });

        await pumpScreen(
          tester,
          product,
          userId: 'buyer-1',
          api: _ClampingShopApi(holds: 2),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(FilledButton, 'Add to cart'));
        await tester.pumpAndSettle();

        expect(find.textContaining('added to your cart'), findsNothing);
        expect(
          find.text('This item could not be added right now.'),
          findsOneWidget,
        );
      },
    );

    const membersProduct = WebshopProduct(
      id: 'p5',
      images: [],
      title: 'Members product',
      regularPrice: 20,
      memberOnly: true,
    );

    testWidgets('refuses a members-only product to a non-member', (
      tester,
    ) async {
      await pumpScreen(tester, membersProduct);
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Members only'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'offers a members-only product to a verified member — the flag is who '
      'it is for, not a blanket prohibition',
      (tester) async {
        await pumpScreen(tester, membersProduct, isMember: true);
        await tester.pumpAndSettle();

        expect(find.widgetWithText(FilledButton, 'Members only'), findsNothing);
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Add to cart'),
        );
        expect(button.onPressed, isNotNull);
      },
    );
  });
}

/// Refuses every stock hold, the way the server does once a product sells out
/// between the product page loading and the buyer tapping add.
class _RejectingShopApi extends ShopApiClient {
  @override
  Future<int> reserve({
    required String productId,
    required int quantity,
    Map<String, String>? customFields,
    Map<String, String>? customFieldLabels,
  }) async {
    throw const ShopApiException(
      'Sold out while you were deciding',
      statusCode: 409,
    );
  }
}

/// Holds a fixed number of units however many are asked for, the way the
/// server does when a product is nearly out of stock.
class _ClampingShopApi extends ShopApiClient {
  _ClampingShopApi({required this.holds});

  final int holds;

  @override
  Future<int> reserve({
    required String productId,
    required int quantity,
    Map<String, String>? customFields,
    Map<String, String>? customFieldLabels,
  }) async {
    return quantity < holds ? quantity : holds;
  }
}
