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
  ///
  /// `List.sort` is documented as unstable, so entries sharing a
  /// `sort_order` (which defaults to 0 in the Appwrite schema) are sorted
  /// with their original list index as a tiebreaker, making the result
  /// deterministic regardless of Dart's sort implementation.
  static List<ProductVariation> listFrom(Object? value) {
    if (value is! List) return const <ProductVariation>[];
    final indexed = value
        .whereType<Map>()
        .map((e) => ProductVariation.fromMap(Map<String, dynamic>.from(e)))
        .where((v) => v.enabled)
        .toList()
        .asMap()
        .entries
        .toList();
    indexed.sort((a, b) {
      final cmp = a.value.sortOrder.compareTo(b.value.sortOrder);
      return cmp != 0 ? cmp : a.key.compareTo(b.key);
    });
    return List.unmodifiable(indexed.map((e) => e.value));
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
