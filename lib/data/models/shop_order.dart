import 'package:equatable/equatable.dart';

/// Where an order stands with the payment provider.
///
/// Mirrors the `orders.status` enum in Appwrite. [pending] is the state an
/// order is created in, before the buyer has paid.
enum ShopOrderStatus {
  pending('pending'),
  authorized('authorized'),
  paid('paid'),
  cancelled('cancelled'),
  failed('failed'),
  refunded('refunded');

  const ShopOrderStatus(this.value);

  final String value;

  static ShopOrderStatus fromValue(String? value) {
    for (final status in ShopOrderStatus.values) {
      if (status.value == value) return status;
    }
    return ShopOrderStatus.pending;
  }

  /// The money is in: the order is fulfillable and the cart can be cleared.
  ///
  /// `authorized` counts — Vipps authorises before capture, and the server
  /// already treats both as settled (it decrements stock and books the revenue
  /// on either), so showing the buyer "pending" at that point would be wrong.
  bool get isSuccessful =>
      this == ShopOrderStatus.paid || this == ShopOrderStatus.authorized;

  /// Terminally unsuccessful — no amount of waiting will change it.
  bool get isFailure =>
      this == ShopOrderStatus.cancelled || this == ShopOrderStatus.failed;

  /// Still waiting on the provider, so it is worth asking again.
  bool get isPending => this == ShopOrderStatus.pending;
}

/// One line of a placed order, as stored at the time of sale.
class ShopOrderItem extends Equatable {
  final String name;
  final int quantity;
  final double unitPrice;
  final double lineTotal;
  final String? productId;
  final String? variationName;

  /// The buyer's answers to the product's checkout questions, in the order
  /// they were asked. Snapshotted with the order, so they survive the question
  /// being relabelled or removed.
  final List<ShopOrderFieldAnswer> customFields;

  const ShopOrderItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.productId,
    this.variationName,
    this.customFields = const <ShopOrderFieldAnswer>[],
  });

  factory ShopOrderItem.fromJson(Map<String, dynamic> json) {
    final unitPrice = (json['unitPrice'] as num?)?.toDouble() ?? 0;
    final quantity = (json['quantity'] as num?)?.toInt() ?? 0;
    return ShopOrderItem(
      name: (json['name'] ?? '').toString(),
      quantity: quantity,
      unitPrice: unitPrice,
      lineTotal: (json['lineTotal'] as num?)?.toDouble() ?? unitPrice * quantity,
      productId: json['productId']?.toString(),
      variationName: json['variationName']?.toString(),
      customFields: (json['customFields'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map(
            (e) => ShopOrderFieldAnswer.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false),
    );
  }

  @override
  List<Object?> get props => [
    name,
    quantity,
    unitPrice,
    lineTotal,
    productId,
    variationName,
    customFields,
  ];
}

/// One answer the buyer gave to a product's checkout question.
class ShopOrderFieldAnswer extends Equatable {
  final String id;
  final String label;
  final String value;

  const ShopOrderFieldAnswer({
    required this.id,
    required this.label,
    required this.value,
  });

  factory ShopOrderFieldAnswer.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    return ShopOrderFieldAnswer(
      id: id,
      label: (json['label'] ?? id).toString(),
      value: (json['value'] ?? '').toString(),
    );
  }

  @override
  List<Object?> get props => [id, label, value];
}

/// A placed order, as returned by `GET /api/payment/orders/{id}`.
class ShopOrder extends Equatable {
  final String id;
  final ShopOrderStatus status;
  final String currency;
  final double subtotal;
  final double discountTotal;
  final double total;
  final bool membershipApplied;
  final double memberDiscountPercent;
  final DateTime? createdAt;
  final String? paymentProvider;

  /// The provider's own receipt, when it issued one.
  final String? receiptUrl;

  /// The still-payable checkout link, for an order the buyer abandoned.
  final String? paymentLink;

  final List<ShopOrderItem> items;

  const ShopOrder({
    required this.id,
    required this.status,
    required this.currency,
    required this.subtotal,
    required this.discountTotal,
    required this.total,
    required this.membershipApplied,
    required this.memberDiscountPercent,
    required this.items,
    this.createdAt,
    this.paymentProvider,
    this.receiptUrl,
    this.paymentLink,
  });

  factory ShopOrder.fromJson(Map<String, dynamic> json) {
    return ShopOrder(
      id: (json['id'] ?? '').toString(),
      status: ShopOrderStatus.fromValue(json['status']?.toString()),
      currency: (json['currency'] ?? 'NOK').toString(),
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      discountTotal: (json['discountTotal'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      membershipApplied: json['membershipApplied'] == true,
      memberDiscountPercent:
          (json['memberDiscountPercent'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      paymentProvider: json['paymentProvider']?.toString(),
      receiptUrl: json['receiptUrl']?.toString(),
      paymentLink: json['paymentLink']?.toString(),
      items: (json['items'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((e) => ShopOrderItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
    );
  }

  /// Builds an order straight from an Appwrite `orders` row.
  ///
  /// Used for the order history list, which reads the rows directly (they carry
  /// a per-buyer read grant) rather than making one API call per order. The
  /// nested `order_items` relationship supplies the lines.
  factory ShopOrder.fromAppwriteRow(Map<String, dynamic> row) {
    final rawItems = row['order_items'];
    return ShopOrder(
      id: (row[r'$id'] ?? '').toString(),
      status: ShopOrderStatus.fromValue(row['status']?.toString()),
      currency: (row['currency'] ?? 'NOK').toString(),
      subtotal: (row['subtotal'] as num?)?.toDouble() ?? 0,
      discountTotal: (row['discount_total'] as num?)?.toDouble() ?? 0,
      total: (row['total'] as num?)?.toDouble() ?? 0,
      membershipApplied: row['membership_applied'] == true,
      memberDiscountPercent:
          (row['member_discount_percent'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse(row[r'$createdAt']?.toString() ?? ''),
      paymentProvider: row['payment_provider']?.toString(),
      receiptUrl:
          row['payment_receipt_url']?.toString() ??
          row['receipt_link']?.toString(),
      paymentLink: row['payment_link']?.toString(),
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map((e) => _itemFromAppwriteRow(Map<String, dynamic>.from(e)))
                .toList(growable: false)
          : const <ShopOrderItem>[],
    );
  }

  static ShopOrderItem _itemFromAppwriteRow(Map<String, dynamic> row) {
    final unitPrice = (row['unit_price'] as num?)?.toDouble() ?? 0;
    final quantity = (row['quantity'] as num?)?.toInt() ?? 0;
    final variation = row['variation'];
    final answers = row['field_answers'];
    return ShopOrderItem(
      name: (row['name'] ?? '').toString(),
      quantity: quantity,
      unitPrice: unitPrice,
      lineTotal: (row['line_total'] as num?)?.toDouble() ?? unitPrice * quantity,
      productId: variationOrRelationId(row['product']),
      variationName: variation is Map ? variation['name']?.toString() : null,
      customFields: answers is List
          ? (answers.whereType<Map>().toList()
                  ..sort(
                    (a, b) => ((a['sort_order'] as num?)?.toInt() ?? 0).compareTo(
                      (b['sort_order'] as num?)?.toInt() ?? 0,
                    ),
                  ))
                .map(
                  (e) => ShopOrderFieldAnswer(
                    id: (e['field_key'] ?? '').toString(),
                    label: (e['label'] ?? e['field_key'] ?? '').toString(),
                    value: (e['value'] ?? '').toString(),
                  ),
                )
                .toList(growable: false)
          : const <ShopOrderFieldAnswer>[],
    );
  }

  /// A relationship column comes back either as a bare id or as the whole row,
  /// depending on how the read selected it.
  static String? variationOrRelationId(Object? value) {
    if (value is String) return value.isEmpty ? null : value;
    if (value is Map) return value[r'$id']?.toString();
    return null;
  }

  int get itemCount =>
      items.fold<int>(0, (sum, item) => sum + item.quantity);

  @override
  List<Object?> get props => [
    id,
    status,
    currency,
    subtotal,
    discountTotal,
    total,
    membershipApplied,
    memberDiscountPercent,
    createdAt,
    paymentProvider,
    receiptUrl,
    paymentLink,
    items,
  ];
}
