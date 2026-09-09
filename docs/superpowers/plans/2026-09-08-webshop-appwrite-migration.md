# Webshop Appwrite Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate webshop products off the failing `api.biso.no` HTTP API onto direct Appwrite reads, and make product variations and custom fields work.

**Architecture:** Mirrors the completed events and jobs migrations. `WebshopService` reads `webshop_products` in one round trip with translations, variations and custom fields all nested via `Query.select`. `WebshopProduct` is a full rewrite — the current model is WooCommerce-shaped and shares almost nothing with the Appwrite row. Model replacement is staged across three tasks so the app compiles and runs after every task.

**Tech Stack:** Flutter 3.47.2 / Dart 3.13.2, `appwrite` Dart SDK (`TablesDB`), `flutter_riverpod`, `equatable`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-07-appwrite-content-migration-design.md`

**Plan 3 of 4.** Plans 1 (shared layer + events) and 2 (jobs) are complete. The shared layer is reused **unchanged**.

## Live data facts (verified 2026-09-08, not assumed)

| Fact | Value | Consequence |
|---|---|---|
| Published products | **50** | |
| Locale coverage | **all 50 bilingual** (`en`+`no`) | Unlike jobs (73 no-only, 21 en-only); fallback still required, less load-bearing |
| Products with **variations** | **0 of 50 published** | See below — the single biggest constraint on this plan |
| Variation rows in total | 26, across **5 products, every one `status: draft`** | Readable, so parsing is verifiable; the UI is not |
| Products with **custom fields** | **7 of 50 published**, 15 fields total | Custom fields ARE live — verifiable against real data |
| Custom field types in use | **all `text`**; `options` empty everywhere | `select` branch will be unverifiable |
| `field_key` format | opaque ids (`69986616186d7`), not readable slugs | Never render `field_key`; always render `label` |
| Image value forms | **22 bare file ids, 3 full URLs** | The shared normalizer is essential, not defensive |
| `member_price` / `member_only` / `stock` | **null on all 50 published** | Product-level member pricing is currently dead data |
| Variation `member_price` | **populated** (e.g. 1500/500, 750/250) | Member pricing is meaningful at the *variation* level |
| `inventory_mode` | `unlimited` on all 50 | Stock display is currently moot |
| `campus_id` values seen | includes **`'5'`** | `AppConstants` only defines `'1'`–`'4'`; do not assume a 1–4 range |

**The variations constraint is the defining fact of this plan.** Every product that has variations is a draft, so no published product exercises the variation code path. Those draft rows are publicly readable, so **parsing can and must be verified against real payloads** — but the variation *UI* cannot be verified against published data. Build it, test it against the real draft payloads, and say plainly that the on-screen path is unverified until a product with variations is published.

**Custom fields are live**, contradicting the earlier assumption that none existed yet. Seven published products carry them, including required fields with Norwegian labels. This path IS verifiable end to end.

## Scope boundary

The spec puts **orders, payments and checkout out of scope**. This plan therefore:

- **Does** model, fetch, and display variations (selecting one changes the displayed price) and custom fields (rendered as a validated form).
- **Does not** submit an order or write `order_items.custom_fields_json`. Collected field values are surfaced to the caller and go no further.

**Deliberate deviation from spec §6 (member pricing).** The spec calls for showing
`member_price` when the user has an active membership, via `membership_service`.
Live data makes that untestable today: `member_price` and `member_only` are null
on **all 50** published products. Building membership gating now would be dead
code with no way to verify it. This plan instead displays a member price only
where one actually exists — which today means variation-level prices — and leaves
membership gating to whenever product-level member pricing is populated.

## Global Constraints

- Database id via `AppConstants.databaseId`, never a literal.
- Always filter `Query.equal('status', 'published')`. The `webshop_products` status enum is `['draft','pending_approval','published','archived']` — note it has four values, unlike events and jobs.
- Nested relations need explicit selection: `Query.select(['*','translation_refs.*','variations.*','custom_fields.*'])`. Webshop uses **`translation_refs`** (like events), not `translations` (jobs).
- **Never** filter by `translation_refs.locale` — it narrows parent rows, not the nested array. Locale is resolved client-side via the shared `resolveLocalizedContent`.
- **Never render a raw Appwrite enum value** (`status`, `inventory_mode`, `cover_pattern`) in the UI. Plan 1 shipped a `published` badge to users this way.
- `description` from `content_translations` is HTML — render via `toFullHtml`, never a bare `Text`.
- Image columns hold bare file ids OR complete URLs; always normalize via `appwriteImageUrl` / `appwriteImageUrls`. Bucket is `media`.
- **Every field added to a model must also be added to `props`.** This project has shipped that gap once.
- Variations and custom fields must both be filtered to `enabled == true` and ordered by `sort_order`.
- Never render `field_key`; it is an opaque id. Render `label`.
- Reuse `ContentTranslation`, `resolveLocalizedContent`, `appwriteImageUrl`, `rowData` unchanged.
- Never `git add -A` / `git add .` / `git commit -a` — the tree carries unrelated WIP. Stage explicit paths.
- Run `flutter analyze` and `flutter test` before each commit.

---

### Task 1: ProductVariation and ProductCustomField models

Purely additive — two new files, no existing code touched.

**Files:**
- Create: `lib/data/models/product_variation.dart`
- Create: `lib/data/models/product_custom_field.dart`
- Test: `test/data/models/product_variation_test.dart`
- Test: `test/data/models/product_custom_field_test.dart`

**Interfaces:**
- Produces: `class ProductVariation` with `final String id, name; final double? regularPrice, memberPrice; final int? stock; final String? sku; final int sortOrder; final bool enabled;` plus `factory ProductVariation.fromMap(Map<String, dynamic>)` and `static List<ProductVariation> listFrom(Object? value)`.
- Produces: `class ProductCustomField` with `final String id, fieldKey, label, type; final bool isRequired, enabled; final String? placeholder, helpText; final List<String> options; final int sortOrder;` plus `factory ProductCustomField.fromMap(Map<String, dynamic>)` and `static List<ProductCustomField> listFrom(Object? value)`.

Both `listFrom` helpers must filter to `enabled == true` and sort by `sortOrder` ascending, so every consumer gets the same ordering without repeating the logic.

- [ ] **Step 1: Write the failing tests**

Payloads are real rows captured from live Appwrite.

`test/data/models/product_variation_test.dart`:

```dart
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
```

`test/data/models/product_custom_field_test.dart`:

```dart
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/data/models/product_variation_test.dart test/data/models/product_custom_field_test.dart`
Expected: FAIL — `Target of URI doesn't exist` for both new model files.

- [ ] **Step 3: Write minimal implementations**

`lib/data/models/product_variation.dart`:

```dart
import 'package:equatable/equatable.dart';

/// One purchasable variant of a webshop product.
///
/// A product with variations prices from the selected variation rather than
/// from the product's own `regular_price`.
class ProductVariation extends Equatable {
  final String id;
  final String name;
  final double? regularPrice;
  final double? memberPrice;
  final int? stock;
  final String? sku;
  final int sortOrder;
  final bool enabled;

  const ProductVariation({
    required this.id,
    required this.name,
    this.regularPrice,
    this.memberPrice,
    this.stock,
    this.sku,
    this.sortOrder = 0,
    this.enabled = true,
  });

  factory ProductVariation.fromMap(Map<String, dynamic> map) {
    return ProductVariation(
      id: (map[r'$id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      regularPrice: (map['regular_price'] as num?)?.toDouble(),
      memberPrice: (map['member_price'] as num?)?.toDouble(),
      stock: (map['stock'] as num?)?.toInt(),
      sku: map['sku']?.toString(),
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      enabled: map['enabled'] != false,
    );
  }

  /// Parses the nested `variations` array, keeping only enabled entries in
  /// `sort_order` order so every consumer sees the same list.
  static List<ProductVariation> listFrom(Object? value) {
    if (value is! List) return const <ProductVariation>[];
    final parsed = value
        .whereType<Map>()
        .map((e) => ProductVariation.fromMap(Map<String, dynamic>.from(e)))
        .where((v) => v.enabled)
        .toList();
    parsed.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return List.unmodifiable(parsed);
  }

  @override
  List<Object?> get props => [
    id,
    name,
    regularPrice,
    memberPrice,
    stock,
    sku,
    sortOrder,
    enabled,
  ];
}
```

`lib/data/models/product_custom_field.dart`:

```dart
import 'package:equatable/equatable.dart';

/// A buyer-supplied field attached to a webshop product.
///
/// `fieldKey` is an opaque Appwrite id, never a readable slug — render
/// [label] to users, and use [fieldKey] only as a map key.
class ProductCustomField extends Equatable {
  final String id;
  final String fieldKey;
  final String label;
  final String type;
  final bool isRequired;
  final String? placeholder;
  final String? helpText;
  final List<String> options;
  final int sortOrder;
  final bool enabled;

  const ProductCustomField({
    required this.id,
    required this.fieldKey,
    required this.label,
    required this.type,
    this.isRequired = false,
    this.placeholder,
    this.helpText,
    this.options = const [],
    this.sortOrder = 0,
    this.enabled = true,
  });

  factory ProductCustomField.fromMap(Map<String, dynamic> map) {
    final rawOptions = map['options'];
    return ProductCustomField(
      id: (map[r'$id'] ?? '').toString(),
      fieldKey: (map['field_key'] ?? '').toString(),
      label: (map['label'] ?? '').toString(),
      type: (map['type'] ?? 'text').toString(),
      isRequired: map['is_required'] == true,
      placeholder: map['placeholder']?.toString(),
      helpText: map['help_text']?.toString(),
      options: rawOptions is List
          ? rawOptions.map((e) => e.toString()).toList(growable: false)
          : const <String>[],
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      enabled: map['enabled'] != false,
    );
  }

  /// Parses the nested `custom_fields` array, keeping only enabled entries in
  /// `sort_order` order.
  static List<ProductCustomField> listFrom(Object? value) {
    if (value is! List) return const <ProductCustomField>[];
    final parsed = value
        .whereType<Map>()
        .map((e) => ProductCustomField.fromMap(Map<String, dynamic>.from(e)))
        .where((f) => f.enabled)
        .toList();
    parsed.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return List.unmodifiable(parsed);
  }

  @override
  List<Object?> get props => [
    id,
    fieldKey,
    label,
    type,
    isRequired,
    placeholder,
    helpText,
    options,
    sortOrder,
    enabled,
  ];
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data/models/product_variation_test.dart test/data/models/product_custom_field_test.dart`
Expected: PASS (9 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/product_variation.dart lib/data/models/product_custom_field.dart \
        test/data/models/product_variation_test.dart test/data/models/product_custom_field_test.dart
git commit -m "feat: add ProductVariation and ProductCustomField models"
```

---

### Task 2: WebshopProduct.fromAppwriteRow

Additive. The existing WooCommerce fields (`id` as `int`, `name`, `price` as `String`, `salePrice`, `url`, `fromFunctionMap`) stay until Task 4 removes them, so consumers keep compiling.

**Files:**
- Modify: `lib/data/models/webshop_product_model.dart`
- Test: `test/data/models/webshop_product_appwrite_test.dart`

**Interfaces:**
- Consumes: `ContentTranslation.listFrom`, `resolveLocalizedContent`, `appwriteImageUrl`, `appwriteImageUrls` (shared layer); `ProductVariation`, `ProductCustomField` (Task 1).
- Produces: `factory WebshopProduct.fromAppwriteRow(Map<String, dynamic> row, {String locale = 'no'})`, plus new fields:
  `final String? rowId, slug, title, shortDescription, htmlDescription, category, campusIdValue, departmentIdValue, linkedEventId, inventoryMode, status; final double regularPriceValue; final double? memberPriceValue; final bool memberOnly; final int? stockValue; final List<String> tags; final List<ProductVariation> variations; final List<ProductCustomField> customFields;`

The existing `images` field is reused rather than duplicated — the Woo model already holds a `List<String> images`, and the factory fills it with normalized URLs. The awkward `…Value` / `…Id` suffixes exist only because the legacy Woo fields occupy those plain names. **Task 4 renames them to the plain names** once the legacy fields are gone.

- [ ] **Step 1: Write the failing test**

Payload is a real published `webshop_products` row with custom fields, captured live.

```dart
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

      expect(p.rowId, 'wpprod61050');
      expect(p.slug, 'co-payment-biso-sweater-trondheim-2025');
      expect(p.campusIdValue, '3');
      expect(p.regularPriceValue, 0);
      expect(p.memberPriceValue, isNull);
      expect(p.memberOnly, isFalse);
      expect(p.inventoryMode, 'unlimited');
      expect(p.stockValue, isNull);
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/webshop_product_appwrite_test.dart`
Expected: FAIL — `The method 'fromAppwriteRow' isn't defined for the type 'WebshopProduct'`

- [ ] **Step 3: Write minimal implementation**

Add the new fields to the field list and constructor as optional parameters with the defaults implied by the test, **add every one of them to `props`**, and add the factory. Do not touch `fromFunctionMap` or any existing field.

```dart
  factory WebshopProduct.fromAppwriteRow(
    Map<String, dynamic> row, {
    String locale = 'no',
  }) {
    final translations = ContentTranslation.listFrom(row['translation_refs']);
    final content = resolveLocalizedContent(translations, locale);

    // `images` is the list column; `image` is the single cover. Prefer the
    // list, fall back to the cover, so a product with only a cover still
    // renders. Both hold either a bare file id or a complete URL.
    var urls = appwriteImageUrls(row['images']);
    if (urls.isEmpty) {
      final cover = appwriteImageUrl(row['image']);
      if (cover != null) urls = <String>[cover];
    }

    return WebshopProduct(
      // Legacy Woo fields, still required until Task 4 removes them.
      id: 0,
      name: content.title,
      images: urls,
      price: (row['regular_price'] ?? 0).toString(),
      salePrice: '',
      // Appwrite-backed fields.
      rowId: (row[r'$id'] ?? '').toString(),
      slug: row['slug']?.toString(),
      title: content.title,
      shortDescription: content.shortDescription,
      htmlDescription: content.description,
      status: (row['status'] ?? 'published').toString(),
      campusIdValue: (row['campus_id'] ?? '').toString(),
      departmentIdValue: row['departmentId']?.toString(),
      regularPriceValue: (row['regular_price'] as num?)?.toDouble() ?? 0,
      memberPriceValue: (row['member_price'] as num?)?.toDouble(),
      memberOnly: row['member_only'] == true,
      category: row['category']?.toString(),
      stockValue: (row['stock'] as num?)?.toInt(),
      inventoryMode: row['inventory_mode']?.toString(),
      linkedEventId: row['linked_event_id']?.toString(),
      tags: (row['tags'] is List)
          ? (row['tags'] as List).map((e) => e.toString()).toList(growable: false)
          : const <String>[],
      variations: ProductVariation.listFrom(row['variations']),
      customFields: ProductCustomField.listFrom(row['custom_fields']),
    );
  }
```

Add imports:

```dart
import '../../core/utils/appwrite_image.dart';
import '../../core/utils/localized_content.dart';
import 'content_translation.dart';
import 'product_custom_field.dart';
import 'product_variation.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/models/webshop_product_appwrite_test.dart`
Expected: PASS (8 tests)

- [ ] **Step 5: Verify nothing else broke**

Run: `flutter analyze && flutter test`
Expected: no new errors; all pre-existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add lib/data/models/webshop_product_model.dart test/data/models/webshop_product_appwrite_test.dart
git commit -m "feat: parse webshop products from Appwrite rows with variations and custom fields"
```

---

### Task 3: WebshopService reads from Appwrite, and the HTTP path is deleted

**Files:**
- Modify: `lib/data/services/webshop_service.dart`
- Modify: `lib/presentation/screens/home/premium_home_screen.dart`
- Modify: `lib/presentation/screens/explore/marketplace_screen.dart`
- Modify: `lib/presentation/screens/explore/webshop_product_detail_screen.dart`
- Modify: `lib/data/services/showcase_navigation_service.dart`
- Test: `test/data/services/webshop_service_query_test.dart`

**Interfaces:**
- Consumes: `WebshopProduct.fromAppwriteRow` (Task 2), `rowData`.
- Produces: `static List<String> WebshopService.buildProductQueries({String? campusId, int limit, int offset, String? search, String? category})`, `static List<String> WebshopService.buildProductCountQueries({String? campusId})`, `Future<List<WebshopProduct>> listProducts({...})`, `Future<int> countProducts({...})`, `Future<WebshopProduct?> getProductById(String id, {String locale})`.

`getProductById` is needed by the detail screen in Task 5; it must use the same `Query.select` so variations and custom fields come back.

Copy the structure of `EventService` / `JobService` — a shared private `_productFilters`, builders on top. It is the twice-reviewed precedent.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:biso/data/services/webshop_service.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher hasQuery(String method, {List<String> containing = const []}) {
  return predicate<List<String>>(
    (queries) => queries.any(
      (q) =>
          q.contains('"method":"$method"') &&
          containing.every((fragment) => q.contains(fragment)),
    ),
    'has a "$method" query containing ${containing.join(', ')}',
  );
}

void main() {
  group('WebshopService.buildProductQueries', () {
    test('always filters to published rows', () {
      expect(
        WebshopService.buildProductQueries(),
        hasQuery('equal', containing: ['status', 'published']),
      );
    });

    test('selects translations, variations and custom fields', () {
      final q = WebshopService.buildProductQueries();
      expect(q, hasQuery('select', containing: ['translation_refs.*']));
      expect(q, hasQuery('select', containing: ['variations.*']));
      expect(q, hasQuery('select', containing: ['custom_fields.*']));
    });

    test('never filters on translation locale', () {
      expect(
        WebshopService.buildProductQueries().any(
          (s) => s.contains('translation_refs.locale'),
        ),
        isFalse,
      );
    });

    test('filters by campus when provided, omits it otherwise', () {
      expect(
        WebshopService.buildProductQueries(campusId: '3'),
        hasQuery('equal', containing: ['campus_id', '"3"']),
      );
      expect(
        WebshopService.buildProductQueries().any((s) => s.contains('campus_id')),
        isFalse,
      );
    });

    test('searches server-side with contains on the translated title', () {
      expect(
        WebshopService.buildProductQueries(search: 'genser'),
        hasQuery('contains', containing: ['translation_refs.title', 'genser']),
      );
    });

    test('omits the search clause for a blank term', () {
      expect(
        WebshopService.buildProductQueries(search: '   ').any(
          (s) => s.contains('translation_refs.title'),
        ),
        isFalse,
      );
    });

    test('applies the requested limit and offset', () {
      final q = WebshopService.buildProductQueries(limit: 37, offset: 40);
      expect(q, hasQuery('limit', containing: ['37']));
      expect(q, hasQuery('offset', containing: ['40']));
    });
  });

  group('WebshopService.buildProductCountQueries', () {
    test('selects only the id, not whole rows or relations', () {
      final q = WebshopService.buildProductCountQueries();
      expect(q, hasQuery('select', containing: [r'$id']));
      expect(q.any((s) => s.contains('variations.*')), isFalse);
      expect(q.any((s) => s.contains('translation_refs.*')), isFalse);
    });

    test('shares the published and campus filters with the list read', () {
      final q = WebshopService.buildProductCountQueries(campusId: '3');
      expect(q, hasQuery('equal', containing: ['status', 'published']));
      expect(q, hasQuery('equal', containing: ['campus_id', '"3"']));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/services/webshop_service_query_test.dart`
Expected: FAIL — `The method 'buildProductQueries' isn't defined for the type 'WebshopService'`

- [ ] **Step 3: Write minimal implementation**

```dart
  static const String collectionId = 'webshop_products';

  /// Filter clauses shared by the list and count reads.
  ///
  /// Locale is intentionally absent: filtering `translation_refs.locale`
  /// narrows parent rows rather than the nested array, which would hide
  /// products lacking that locale. Locale is resolved client-side.
  static List<String> _productFilters({String? campusId, String? search, String? category}) {
    final queries = <String>[Query.equal('status', 'published')];

    if (campusId != null && campusId.isNotEmpty) {
      queries.add(Query.equal('campus_id', campusId));
    }
    if (category != null && category.isNotEmpty) {
      queries.add(Query.equal('category', category));
    }

    final term = search?.trim() ?? '';
    if (term.isNotEmpty) {
      queries.add(Query.contains('translation_refs.title', [term]));
    }

    return queries;
  }

  static List<String> buildProductQueries({
    String? campusId,
    int limit = 20,
    int offset = 0,
    String? search,
    String? category,
  }) {
    return [
      ..._productFilters(campusId: campusId, search: search, category: category),
      // Nested relations are only returned when explicitly selected.
      Query.select([
        '*',
        'translation_refs.*',
        'variations.*',
        'custom_fields.*',
      ]),
      Query.orderDesc(r'$createdAt'),
      Query.limit(limit),
      Query.offset(offset),
    ];
  }

  static List<String> buildProductCountQueries({String? campusId}) {
    return [
      ..._productFilters(campusId: campusId),
      Query.select([r'$id']),
      Query.limit(1),
    ];
  }

  Future<List<WebshopProduct>> listProducts({
    String? campusId,
    String locale = 'no',
    int limit = 20,
    int offset = 0,
    String? search,
    String? category,
  }) async {
    final response = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      queries: buildProductQueries(
        campusId: campusId,
        limit: limit,
        offset: offset,
        search: search,
        category: category,
      ),
    );

    return response.rows
        .map((row) => WebshopProduct.fromAppwriteRow(rowData(row), locale: locale))
        .toList(growable: false);
  }

  Future<int> countProducts({String? campusId}) async {
    final response = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      queries: buildProductCountQueries(campusId: campusId),
    );
    return response.total;
  }

  Future<WebshopProduct?> getProductById(String id, {String locale = 'no'}) async {
    final response = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      queries: [
        Query.equal(r'$id', id),
        Query.equal('status', 'published'),
        Query.select([
          '*',
          'translation_refs.*',
          'variations.*',
          'custom_fields.*',
        ]),
        Query.limit(1),
      ],
    );
    if (response.rows.isEmpty) return null;
    return WebshopProduct.fromAppwriteRow(
      rowData(response.rows.first),
      locale: locale,
    );
  }
```

Then delete `listWebshopProducts` and its `http` import, and repoint every caller to `listProducts`, passing `ref.watch(localeProvider).languageCode` where a `ref` is available.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data/services/webshop_service_query_test.dart`
Expected: PASS (9 tests)

- [ ] **Step 5: Verify the HTTP path is gone**

Run: `flutter analyze && flutter test`
Run: `grep -rn "listWebshopProducts\|wc-products\|fnSyncWebshopProductsId" lib/` — expected: no hits.

- [ ] **Step 6: Verify against live Appwrite**

```bash
curl -s -H "X-Appwrite-Project: biso" \
  "https://appwrite.biso.no/v1/tablesdb/app/tables/webshop_products/rows?queries%5B%5D=%7B%22method%22%3A%22equal%22%2C%22attribute%22%3A%22status%22%2C%22values%22%3A%5B%22published%22%5D%7D" \
  | python3 -c "import json,sys; print('published products:', json.load(sys.stdin)['total'])"
```
Expected: 50.

- [ ] **Step 7: Commit**

```bash
git add lib/data/services/webshop_service.dart test/data/services/webshop_service_query_test.dart \
        lib/presentation/screens/home/premium_home_screen.dart \
        lib/presentation/screens/explore/marketplace_screen.dart \
        lib/presentation/screens/explore/webshop_product_detail_screen.dart \
        lib/data/services/showcase_navigation_service.dart
git commit -m "feat: read webshop products from Appwrite and drop the HTTP path"
```

---

### Task 4: Remove the WooCommerce fields and rename to plain names

**Files:**
- Modify: `lib/data/models/webshop_product_model.dart`
- Delete: `test/data/models/webshop_product_model_test.dart`
- Modify: consumers surfaced by `flutter analyze`

- [ ] **Step 1: Remove the legacy fields and constructor**

Delete `fromFunctionMap`, the `int id`, `name`, `price` (`String`), `salePrice`, `url`, `campusLabel`, `departmentLabel`, `hasSale`, and every private Woo helper only they used.

Delete `test/data/models/webshop_product_model_test.dart` (use `git rm`) — it tests only `fromFunctionMap`, and Task 2 replaced its coverage.

- [ ] **Step 2: Rename the suffixed fields to their plain names**

`rowId` → `id`, `campusIdValue` → `campusId`, `departmentIdValue` → `departmentId`, `regularPriceValue` → `regularPrice`, `memberPriceValue` → `memberPrice`, `stockValue` → `stock`.

Update `props` to match the surviving field list **exactly** — count both lists.

- [ ] **Step 3: Fix consumers**

Run: `flutter analyze` and fix every error it reports.

Do not invent data to keep a widget alive: `member_price`, `member_only` and `stock` are null on all 50 published products, so any UI that existed only to show them should be removed or hidden when null, not filled with a placeholder. Do not render a raw `status` or `inventory_mode` enum value.

- [ ] **Step 4: Verify**

Run: `flutter analyze && flutter test`
Expected: no errors, all tests pass.

- [ ] **Step 5: Commit**

Stage each file you actually changed, by explicit path — `flutter analyze` in
Step 3 tells you exactly which. For example:

```bash
git rm test/data/models/webshop_product_model_test.dart
git add lib/data/models/webshop_product_model.dart \
        lib/presentation/screens/explore/marketplace_screen.dart \
        lib/presentation/screens/explore/webshop_product_detail_screen.dart \
        lib/presentation/screens/home/premium_home_screen.dart
git commit -m "refactor: drop WooCommerce fields from WebshopProduct"
```

Never `git add lib/` or any directory — the tree carries unrelated WIP. Run
`git status --short` before committing and confirm only your own files are staged.

---

### Task 5: Variations and custom fields on the product detail screen

**Files:**
- Modify: `lib/presentation/screens/explore/webshop_product_detail_screen.dart`

**Interfaces:**
- Consumes: `WebshopProduct.variations`, `WebshopProduct.customFields`, `WebshopService.getProductById`.

- [ ] **Step 1: Render variation selection**

When `product.variations` is non-empty, show a selector (the list is already filtered to enabled and sorted). Selecting a variation updates the displayed price: use the variation's `regularPrice` when set, otherwise the product's. Show `memberPrice` alongside only when the variation actually has one — it is null for many.

When `variations` is empty, price from the product exactly as today. **No published product currently has variations**, so this branch is what all 50 live products exercise; do not regress it.

- [ ] **Step 2: Render the custom-field form**

For each entry in `product.customFields`, render an input appropriate to `type`:
`text` → single-line, `textarea` → multi-line, `number` → numeric keyboard, `email` → email keyboard, `select` → dropdown over `options`.

Render `label` as the field label and `placeholder` / `helpText` where present. **Never render `fieldKey`** — it is an opaque id like `69986616186d7`.

Mark required fields and validate them: a required field left blank blocks the primary action and shows an error. Seven live products have required fields, so this path is reachable today.

Only `text` occurs in live data; `select` has no live example, so its branch is unverified — say so in your report rather than claiming it works.

- [ ] **Step 3: Collect values without submitting**

Collected values live in screen state, keyed by `fieldKey`, ready for a future checkout. **Do not write an order or call any order/payment API** — orders are out of scope per the spec.

- [ ] **Step 4: Verify**

Run: `flutter analyze && flutter test`

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/screens/explore/webshop_product_detail_screen.dart
git commit -m "feat: variation selection and custom-field form on product detail"
```

---

## Verification

- `flutter analyze` reports no errors; `flutter test` passes.
- The webshop section renders 50 published products with real titles and images, replacing the current "Failed to load content".
- A product with custom fields (e.g. `wpprod61050`, "Co-payment – BISO sweater Trondheim 2025") shows three required fields with Norwegian labels, and blocks the primary action while any is blank.
- `grep -rn "api.biso.no" lib/` shows hits only in expense code.

## Known limits to state plainly, not paper over

- **No published product has variations**, so the variation UI is unverified on device. Parsing is verified against the five real draft payloads.
- **`select`-type custom fields have no live example**; that branch is unverified.
- **Product-level `member_price`, `member_only` and `stock` are null across all 50 published products.** Variation-level `member_price` is populated, so member pricing is meaningful only there today.

## Follow-on

4. Screen audit — including `AppConfig.eventsSource` / `jobsSource` / `productsSource`, which are all inert once this plan lands and should be removed together.
