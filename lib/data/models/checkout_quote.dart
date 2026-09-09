import 'package:equatable/equatable.dart';

/// The server's answer to "what will this cart actually cost?".
///
/// The app never prices a cart itself. Variation pricing, the member discount
/// and the membership lookup that decides whether the discount applies all live
/// on the server, and the checkout endpoint rejects a request whose total
/// disagrees with its own. So the checkout screen shows what
/// `POST /api/payment/checkout/quote` returned, and hands that same total back
/// when the buyer pays — the displayed price and the charged price are the same
/// number by construction.
class CheckoutQuote extends Equatable {
  final String currency;
  final double subtotal;
  final double discountTotal;
  final double total;
  final bool membershipApplied;
  final double memberDiscountPercent;
  final List<CheckoutQuoteLine> items;

  const CheckoutQuote({
    required this.currency,
    required this.subtotal,
    required this.discountTotal,
    required this.total,
    required this.membershipApplied,
    required this.memberDiscountPercent,
    required this.items,
  });

  /// What the cart would have cost without the member discount.
  double get originalTotal => total + discountTotal;

  factory CheckoutQuote.fromJson(Map<String, dynamic> json) {
    return CheckoutQuote(
      currency: (json['currency'] ?? 'NOK').toString(),
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      discountTotal: (json['discountTotal'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      membershipApplied: json['membershipApplied'] == true,
      memberDiscountPercent:
          (json['memberDiscountPercent'] as num?)?.toDouble() ?? 0,
      items: (json['items'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((e) => CheckoutQuoteLine.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
    );
  }

  @override
  List<Object?> get props => [
    currency,
    subtotal,
    discountTotal,
    total,
    membershipApplied,
    memberDiscountPercent,
    items,
  ];
}

/// One priced line of a [CheckoutQuote].
class CheckoutQuoteLine extends Equatable {
  final String productId;
  final String name;
  final String title;
  final int quantity;
  final double unitPrice;
  final double lineTotal;
  final String? variationId;
  final String? variationName;

  const CheckoutQuoteLine({
    required this.productId,
    required this.name,
    required this.title,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.variationId,
    this.variationName,
  });

  factory CheckoutQuoteLine.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] ?? '').toString();
    return CheckoutQuoteLine(
      productId: (json['productId'] ?? '').toString(),
      name: name,
      title: (json['title'] ?? name).toString(),
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
      lineTotal: (json['lineTotal'] as num?)?.toDouble() ?? 0,
      variationId: json['variationId']?.toString(),
      variationName: json['variationName']?.toString(),
    );
  }

  @override
  List<Object?> get props => [
    productId,
    name,
    title,
    quantity,
    unitPrice,
    lineTotal,
    variationId,
    variationName,
  ];
}
