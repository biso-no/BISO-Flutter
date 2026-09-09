import 'package:equatable/equatable.dart';

import 'product_custom_field.dart';
import 'product_variation.dart';
import 'webshop_product_model.dart';

/// One line in the shopping cart.
///
/// A line is a *configuration* of a product, not just a product: the same
/// hoodie in two sizes, or two tickets with different names filled in, are two
/// lines. [lineId] captures that — it folds the product, the chosen variation
/// and the buyer's answers into one key — so adding the same configuration
/// again increments a quantity while a different one starts its own line.
///
/// The prices here are for display only. Every amount that is actually charged
/// is recomputed server-side (`POST /api/payment/checkout/quote`, then again by
/// the checkout route), because the member discount depends on a membership
/// lookup the app cannot perform and must not guess at.
class CartItem extends Equatable {
  final String lineId;
  final String productId;
  final String? slug;
  final String name;
  final String? imageUrl;
  final String? variationId;
  final String? variationName;

  /// Indicative unit price: the variation's price when one is selected,
  /// otherwise the product's. Superseded by the server quote at checkout.
  final double unitPrice;

  /// Indicative member price, when the product or variation advertises one.
  final double? memberPrice;

  final int quantity;

  /// Answers to the product's checkout questions, keyed by `field_key`.
  final Map<String, String> customFields;

  /// The question each answer was given to, keyed the same way. Carried so the
  /// cart can name an answer without re-reading the product, and so the order
  /// line records what was asked even if the question is later relabelled.
  final Map<String, String> customFieldLabels;

  /// Stock snapshot at the time of adding, or `null` when untracked. Used only
  /// to keep the stepper honest; the server is what actually enforces it.
  final int? stock;

  /// Per-order cap from the product metadata, when it sets one.
  final int? maxPerOrder;

  const CartItem({
    required this.lineId,
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    this.slug,
    this.imageUrl,
    this.variationId,
    this.variationName,
    this.memberPrice,
    this.customFields = const <String, String>{},
    this.customFieldLabels = const <String, String>{},
    this.stock,
    this.maxPerOrder,
  });

  /// The identity of a cart line: same product, same variation, same answers.
  ///
  /// Answers are sorted before being folded in so two identical configurations
  /// entered in a different order still collapse onto one line.
  static String buildLineId({
    required String productId,
    String? variationId,
    Map<String, String> customFields = const <String, String>{},
  }) {
    final answers = customFields.entries
        .where((entry) => entry.value.trim().isNotEmpty)
        .map((entry) => '${entry.key}=${entry.value.trim()}')
        .toList()
      ..sort();
    return [productId, variationId ?? '', answers.join(',')].join('#');
  }

  /// Builds a line from a product the buyer is looking at.
  factory CartItem.fromProduct({
    required WebshopProduct product,
    ProductVariation? variation,
    int quantity = 1,
    Map<String, String> customFields = const <String, String>{},
    List<ProductCustomField> customFieldDefinitions =
        const <ProductCustomField>[],
  }) {
    final answers = <String, String>{
      for (final entry in customFields.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
    };
    final labels = <String, String>{
      for (final field in customFieldDefinitions)
        if (answers.containsKey(field.fieldKey)) field.fieldKey: field.label,
    };

    return CartItem(
      lineId: buildLineId(
        productId: product.id,
        variationId: variation?.id,
        customFields: answers,
      ),
      productId: product.id,
      slug: product.slug,
      name: product.title ?? product.slug ?? 'Product',
      imageUrl: product.images.isEmpty ? null : product.images.first,
      variationId: variation?.id,
      variationName: variation?.name,
      unitPrice: variation?.regularPrice ?? product.regularPrice,
      memberPrice: variation?.memberPrice ?? product.memberPrice,
      quantity: quantity,
      customFields: answers,
      customFieldLabels: labels,
      // A variation carries its own stock; fall back to the product's.
      stock: variation?.stock ?? product.stock,
    );
  }

  /// The name shown on the order line and the payment provider's receipt.
  ///
  /// The variation has to be folded in here: the checkout API stores the line's
  /// display name from this title, so a bare product name would leave the
  /// receipt and the fulfilment list unable to tell a Small from a Large. The
  /// variation is *also* stored structurally on the line — this is the
  /// human-readable half.
  String get checkoutTitle =>
      variationName == null || variationName!.isEmpty
      ? name
      : '$name — $variationName';

  double get lineTotal => unitPrice * quantity;

  CartItem copyWith({int? quantity}) {
    return CartItem(
      lineId: lineId,
      productId: productId,
      slug: slug,
      name: name,
      imageUrl: imageUrl,
      variationId: variationId,
      variationName: variationName,
      unitPrice: unitPrice,
      memberPrice: memberPrice,
      quantity: quantity ?? this.quantity,
      customFields: customFields,
      customFieldLabels: customFieldLabels,
      stock: stock,
      maxPerOrder: maxPerOrder,
    );
  }

  Map<String, dynamic> toJson() => {
    'lineId': lineId,
    'productId': productId,
    'slug': slug,
    'name': name,
    'imageUrl': imageUrl,
    'variationId': variationId,
    'variationName': variationName,
    'unitPrice': unitPrice,
    'memberPrice': memberPrice,
    'quantity': quantity,
    'customFields': customFields,
    'customFieldLabels': customFieldLabels,
    'stock': stock,
    'maxPerOrder': maxPerOrder,
  };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    Map<String, String> stringMap(Object? value) {
      if (value is! Map) return const <String, String>{};
      return {
        for (final entry in value.entries)
          entry.key.toString(): entry.value?.toString() ?? '',
      };
    }

    final productId = (json['productId'] ?? '').toString();
    final variationId = json['variationId']?.toString();
    final customFields = stringMap(json['customFields']);

    return CartItem(
      // Recomputed rather than trusted, so a line stored by an older build
      // still collapses correctly against a newly added one.
      lineId: buildLineId(
        productId: productId,
        variationId: variationId,
        customFields: customFields,
      ),
      productId: productId,
      slug: json['slug']?.toString(),
      name: (json['name'] ?? '').toString(),
      imageUrl: json['imageUrl']?.toString(),
      variationId: variationId,
      variationName: json['variationName']?.toString(),
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
      memberPrice: (json['memberPrice'] as num?)?.toDouble(),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      customFields: customFields,
      customFieldLabels: stringMap(json['customFieldLabels']),
      stock: (json['stock'] as num?)?.toInt(),
      maxPerOrder: (json['maxPerOrder'] as num?)?.toInt(),
    );
  }

  /// The line as the checkout and quote endpoints expect it. Deliberately
  /// carries no price: the server recomputes every amount from its own rows.
  Map<String, dynamic> toCheckoutPayload() => {
    'productId': productId,
    'quantity': quantity,
    if (slug != null && slug!.isNotEmpty) 'slug': slug,
    'title': checkoutTitle,
    if (variationId != null) 'variationId': variationId,
    if (customFields.isNotEmpty) 'customFields': customFields,
    if (customFieldLabels.isNotEmpty) 'customFieldLabels': customFieldLabels,
  };

  @override
  List<Object?> get props => [
    lineId,
    productId,
    slug,
    name,
    imageUrl,
    variationId,
    variationName,
    unitPrice,
    memberPrice,
    quantity,
    customFields,
    customFieldLabels,
    stock,
    maxPerOrder,
  ];
}
