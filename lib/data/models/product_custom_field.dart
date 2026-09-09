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
  ///
  /// `List.sort` is documented as unstable, so entries sharing a
  /// `sort_order` (which defaults to 0 in the Appwrite schema) are sorted
  /// with their original list index as a tiebreaker, making the result
  /// deterministic regardless of Dart's sort implementation.
  static List<ProductCustomField> listFrom(Object? value) {
    if (value is! List) return const <ProductCustomField>[];
    final indexed = value
        .whereType<Map>()
        .map((e) => ProductCustomField.fromMap(Map<String, dynamic>.from(e)))
        .where((f) => f.enabled)
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
