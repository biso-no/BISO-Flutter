import 'package:equatable/equatable.dart';

import '../../core/utils/appwrite_image.dart';
import '../../core/utils/localized_content.dart';
import 'content_translation.dart';
import 'product_custom_field.dart';
import 'product_variation.dart';

class WebshopProduct extends Equatable {
  final int id;
  final String name;
  final String? campusId;
  final String? campusLabel;
  final String? departmentId;
  final String? departmentLabel;
  final List<String> images;
  final String price; // Woo returns price as string
  final String salePrice;
  final String? description;
  final String? url;

  // Appwrite-backed fields (Task 2). These temporarily carry `…Value` /
  // `rowId` / `htmlDescription` suffixes because the legacy Woo fields above
  // still occupy the plain names (`id`, `campusId`, `departmentId`,
  // `description`). Task 4 renames them once the legacy fields are removed.
  final String? rowId;
  final String? slug;
  final String? title;
  final String? shortDescription;
  final String? htmlDescription;
  final String? category;
  final String? campusIdValue;
  final String? departmentIdValue;
  final String? linkedEventId;
  final String? inventoryMode;
  final String? status;
  final double regularPriceValue;
  final double? memberPriceValue;
  final bool memberOnly;
  final int? stockValue;
  final List<String> tags;
  final List<ProductVariation> variations;
  final List<ProductCustomField> customFields;

  const WebshopProduct({
    required this.id,
    required this.name,
    required this.images,
    required this.price,
    required this.salePrice,
    this.campusId,
    this.campusLabel,
    this.departmentId,
    this.departmentLabel,
    this.description,
    this.url,
    this.rowId,
    this.slug,
    this.title,
    this.shortDescription,
    this.htmlDescription,
    this.category,
    this.campusIdValue,
    this.departmentIdValue,
    this.linkedEventId,
    this.inventoryMode,
    this.status,
    this.regularPriceValue = 0,
    this.memberPriceValue,
    this.memberOnly = false,
    this.stockValue,
    this.tags = const <String>[],
    this.variations = const <ProductVariation>[],
    this.customFields = const <ProductCustomField>[],
  });

  factory WebshopProduct.fromFunctionMap(Map<String, dynamic> map) {
    final metadata = _metadataMap(map['meta_data']);
    final campusId = _stringValue(
      map['campus_id'] ?? map['campusId'] ?? metadata['campus'],
    );
    MapEntry<String, dynamic>? departmentEntry;
    for (final entry in metadata.entries) {
      if (entry.key.startsWith('department_') &&
          !entry.key.startsWith('_department_')) {
        departmentEntry = entry;
        break;
      }
    }
    final departmentId = _stringValue(
      map['department_id'] ?? map['departmentId'] ?? departmentEntry?.value,
    );

    return WebshopProduct(
      id: (map['id'] ?? 0) as int,
      name: (map['name'] ?? '') as String,
      images: _parseImages(map['images']),
      price: (map['price'] ?? '') as String,
      salePrice: (map['sale_price'] ?? '') as String,
      campusId: campusId,
      campusLabel:
          _labelFromObject(map['campus']) ?? _campusLabelFromId(campusId),
      departmentId: departmentId,
      departmentLabel: _labelFromObject(map['department']),
      description: map['description'] as String?,
      url: (map['url'] ?? map['permalink']) as String?,
    );
  }

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

  bool get hasSale => salePrice.isNotEmpty && salePrice != '0';

  @override
  List<Object?> get props => [
    id,
    name,
    campusId,
    campusLabel,
    departmentId,
    departmentLabel,
    images,
    price,
    salePrice,
    url,
    rowId,
    slug,
    title,
    shortDescription,
    htmlDescription,
    category,
    campusIdValue,
    departmentIdValue,
    linkedEventId,
    inventoryMode,
    status,
    regularPriceValue,
    memberPriceValue,
    memberOnly,
    stockValue,
    tags,
    variations,
    customFields,
  ];

  static Map<String, dynamic> _metadataMap(dynamic value) {
    if (value is! List) return const <String, dynamic>{};
    return {
      for (final item in value)
        if (item is Map<String, dynamic> && item['key'] != null)
          item['key'].toString(): item['value'],
    };
  }

  static List<String> _parseImages(dynamic value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) {
          if (item is String) return item;
          if (item is Map<String, dynamic>) {
            return (item['src'] ?? item['url'] ?? item['thumbnail'])
                ?.toString();
          }
          return null;
        })
        .whereType<String>()
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static String? _labelFromObject(dynamic value) {
    if (value is Map<String, dynamic>) {
      return _stringValue(value['label'] ?? value['name']);
    }
    return null;
  }

  static String? _stringValue(dynamic value) {
    final stringValue = value?.toString().trim();
    return stringValue == null || stringValue.isEmpty ? null : stringValue;
  }

  static String? _campusLabelFromId(String? campusId) {
    switch (campusId) {
      case '1':
        return 'Oslo';
      case '2':
        return 'Bergen';
      case '3':
        return 'Trondheim';
      case '4':
        return 'Stavanger';
      default:
        return null;
    }
  }
}
