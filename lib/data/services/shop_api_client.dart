import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../models/cart_item.dart';
import '../models/checkout_quote.dart';
import '../models/payment_provider.dart';
import '../models/shop_order.dart';
import 'appwrite_service.dart';

/// A failure reported by the shop API, with the server's own message.
///
/// The messages are written for buyers ("Only 2 of BISO Hoodie available",
/// "Vipps payment is currently unavailable"), so they are surfaced as-is
/// rather than replaced with a generic string.
class ShopApiException implements Exception {
  final String message;
  final int? statusCode;

  const ShopApiException(this.message, {this.statusCode});

  /// The cart cannot be fulfilled as it stands — out of stock, or over a
  /// purchase limit. Worth re-reading the cart rather than retrying.
  bool get isConflict => statusCode == 409;

  /// The session is gone or was never there; the buyer needs to sign in.
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// The app's client for the shop endpoints on `apps/api`.
///
/// Everything here exists because the app has no server of its own. Prices,
/// provider availability and payment outcomes are all decided server-side; this
/// class asks, and never computes.
class ShopApiClient {
  ShopApiClient({http.Client? httpClient}) : _httpClient = httpClient;

  final http.Client? _httpClient;

  static const Duration _timeout = Duration(seconds: 20);

  /// Which providers may be offered right now.
  ///
  /// Unauthenticated: the answer is the same for everyone and says nothing
  /// beyond which buttons to draw.
  Future<List<PaymentProviderAvailability>> fetchProviders() async {
    final data = await _send(
      method: 'GET',
      path: '/api/payment/providers',
      authenticated: false,
    );
    final providers = data['providers'];
    if (providers is! List) return const <PaymentProviderAvailability>[];
    return providers
        .whereType<Map>()
        .map(
          (e) => PaymentProviderAvailability.fromJson(
            Map<String, dynamic>.from(e),
          ),
        )
        .whereType<PaymentProviderAvailability>()
        .toList(growable: false);
  }

  /// Prices a cart without creating anything.
  ///
  /// Throws a [ShopApiException] with `isConflict` set when a line cannot be
  /// fulfilled, which is the point of asking before the buyer commits.
  Future<CheckoutQuote> quote(List<CartItem> items) async {
    final data = await _send(
      method: 'POST',
      path: '/api/payment/checkout/quote',
      body: {
        'items': items
            .map((item) => item.toCheckoutPayload())
            .toList(growable: false),
      },
    );
    return CheckoutQuote.fromJson(data);
  }

  /// Creates the order and the payment session, and returns where to send the
  /// buyer.
  ///
  /// [total] must be the total from a [quote] for the same cart: the server
  /// recomputes it and refuses the request if the two disagree.
  Future<StartedCheckout> startCheckout({
    required PaymentProvider provider,
    required List<CartItem> items,
    required double subtotal,
    required double total,
    required String email,
    String? firstName,
    String? lastName,
    String? phone,
  }) async {
    final data = await _send(
      method: 'POST',
      path: '/api/payment/${provider.id}/checkout',
      body: {
        // Tells the return route to deep-link back into the app once it has
        // reconciled the payment, instead of rendering the web receipt.
        'client': 'app',
        'currency': 'NOK',
        'customerInfo': {
          'email': email,
          if (firstName != null && firstName.isNotEmpty) 'firstName': firstName,
          if (lastName != null && lastName.isNotEmpty) 'lastName': lastName,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
        },
        'items': items
            .map((item) => item.toCheckoutPayload())
            .toList(growable: false),
        'reference': _checkoutReference(),
        'subtotal': subtotal,
        'total': total,
      },
    );

    final checkoutUrl = data['checkoutUrl']?.toString();
    final orderId = data['orderId']?.toString();
    if (checkoutUrl == null ||
        checkoutUrl.isEmpty ||
        orderId == null ||
        orderId.isEmpty) {
      throw const ShopApiException('Checkout could not be started.');
    }
    return StartedCheckout(checkoutUrl: checkoutUrl, orderId: orderId);
  }

  /// Reads one of the buyer's own orders, re-synced with the provider first.
  ///
  /// This is how the app learns a payment succeeded when the buyer came back by
  /// switching apps rather than following the redirect.
  Future<ShopOrder> fetchOrder(String orderId) async {
    final data = await _send(
      method: 'GET',
      path: '/api/payment/orders/${Uri.encodeComponent(orderId)}',
    );
    return ShopOrder.fromJson(data);
  }

  /// Holds stock for one cart line, returning the quantity actually held.
  ///
  /// The server caps to live availability, so the returned quantity may be
  /// lower than requested and is what the cart should show.
  Future<int> reserve({
    required String productId,
    required int quantity,
    Map<String, String>? customFields,
    Map<String, String>? customFieldLabels,
  }) async {
    final data = await _send(
      method: 'PUT',
      path: '/api/shop/cart',
      body: {
        'productId': productId,
        'quantity': quantity,
        if (customFields != null && customFields.isNotEmpty) ...{
          'customFields': customFields,
          'customFieldLabels': customFieldLabels ?? const <String, String>{},
        },
      },
    );
    return (data['quantity'] as num?)?.toInt() ?? quantity;
  }

  /// Releases the hold on one product, or on the whole cart when [productId]
  /// is omitted.
  Future<void> releaseReservation({String? productId}) async {
    await _send(
      method: 'DELETE',
      path: '/api/shop/cart',
      query: productId == null ? null : {'productId': productId},
    );
  }

  /// A per-attempt reference for the payment provider. The order id is the
  /// provider-facing reference for Vipps, so this only needs to be unique
  /// enough to tell two attempts apart in logs.
  String _checkoutReference() =>
      'app-${DateTime.now().millisecondsSinceEpoch}-'
      '${DateTime.now().microsecond}';

  Future<Map<String, dynamic>> _send({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool authenticated = true,
  }) async {
    final client = _httpClient ?? http.Client();
    final shouldClose = _httpClient == null;
    try {
      final headers = <String, String>{
        if (body != null) 'content-type': 'application/json',
        if (authenticated) ...await _authHeaders(),
      };
      final uri = _apiUri(path, query);
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) {
        request.body = jsonEncode(body);
      }

      final streamed = await client.send(request).timeout(_timeout);
      final responseBody = await streamed.stream.bytesToString();
      return _decode(responseBody, streamed.statusCode);
    } finally {
      if (shouldClose) client.close();
    }
  }

  Future<Map<String, String>> _authHeaders() async {
    try {
      final jwt = await account.createJWT();
      return {'Authorization': 'Bearer ${jwt.jwt}'};
    } catch (_) {
      // No session. Let the request go out unauthenticated so the server
      // answers with its own 401 and the UI can prompt for sign-in once.
      return const <String, String>{};
    }
  }

  Uri _apiUri(String path, Map<String, String>? query) {
    final base = AppConstants.apiBaseUrl.endsWith('/')
        ? AppConstants.apiBaseUrl.substring(
            0,
            AppConstants.apiBaseUrl.length - 1,
          )
        : AppConstants.apiBaseUrl;
    return Uri.parse(
      '$base$path',
    ).replace(queryParameters: query == null || query.isEmpty ? null : query);
  }

  Map<String, dynamic> _decode(String body, int statusCode) {
    Object? decoded;
    try {
      decoded = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
    } catch (_) {
      decoded = null;
    }
    final map = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'data': decoded};

    if (statusCode < 200 || statusCode >= 300) {
      throw ShopApiException(
        (map['message'] ?? map['error'] ?? 'Something went wrong.').toString(),
        statusCode: statusCode,
      );
    }
    return map;
  }
}

/// A payment session that is waiting for the buyer.
class StartedCheckout {
  final String checkoutUrl;
  final String orderId;

  const StartedCheckout({required this.checkoutUrl, required this.orderId});
}
