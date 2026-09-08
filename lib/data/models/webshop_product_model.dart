import 'package:equatable/equatable.dart';

import '../../core/utils/appwrite_image.dart';
import '../../core/utils/localized_content.dart';
import 'content_translation.dart';
import 'product_custom_field.dart';
import 'product_variation.dart';

class WebshopProduct extends Equatable {
  final String id;
  final List<String> images;
  final String? slug;
  final String? title;
  final String? shortDescription;
  final String? description;
  final String? category;
  final String? campusId;
  final String? departmentId;
  final String? linkedEventId;
  final String? inventoryMode;
  final String? status;
  final double regularPrice;
  final double? memberPrice;
  final bool memberOnly;
  final int? stock;
  final List<String> tags;
  final List<ProductVariation> variations;
  final List<ProductCustomField> customFields;

  const WebshopProduct({
    required this.id,
    required this.images,
    this.slug,
    this.title,
    this.shortDescription,
    this.description,
    this.category,
    this.campusId,
    this.departmentId,
    this.linkedEventId,
    this.inventoryMode,
    this.status,
    this.regularPrice = 0,
    this.memberPrice,
    this.memberOnly = false,
    this.stock,
    this.tags = const <String>[],
    this.variations = const <ProductVariation>[],
    this.customFields = const <ProductCustomField>[],
  });

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
      id: (row[r'$id'] ?? '').toString(),
      images: urls,
      slug: row['slug']?.toString(),
      title: content.title,
      shortDescription: content.shortDescription,
      description: content.description,
      status: (row['status'] ?? 'published').toString(),
      campusId: (row['campus_id'] ?? '').toString(),
      departmentId: row['departmentId']?.toString(),
      regularPrice: (row['regular_price'] as num?)?.toDouble() ?? 0,
      memberPrice: (row['member_price'] as num?)?.toDouble(),
      memberOnly: row['member_only'] == true,
      category: row['category']?.toString(),
      stock: (row['stock'] as num?)?.toInt(),
      inventoryMode: row['inventory_mode']?.toString(),
      linkedEventId: row['linked_event_id']?.toString(),
      tags: (row['tags'] is List)
          ? (row['tags'] as List).map((e) => e.toString()).toList(growable: false)
          : const <String>[],
      variations: ProductVariation.listFrom(row['variations']),
      customFields: ProductCustomField.listFrom(row['custom_fields']),
    );
  }

  @override
  List<Object?> get props => [
    id,
    images,
    slug,
    title,
    shortDescription,
    description,
    category,
    campusId,
    departmentId,
    linkedEventId,
    inventoryMode,
    status,
    regularPrice,
    memberPrice,
    memberOnly,
    stock,
    tags,
    variations,
    customFields,
  ];
}
