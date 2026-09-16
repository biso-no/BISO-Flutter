import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/membership_overview.dart';
import '../models/payment_provider.dart';
import 'api_auth.dart';
import 'shop_api_client.dart' show StartedCheckout;

/// A membership request the server refused, with its message.
class MembershipApiException implements Exception {
  const MembershipApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  /// The payment provider has been switched off since the list was loaded.
  bool get isProviderDisabled => statusCode == 403;

  /// The student's cover already reaches the plan's end.
  bool get isAlreadyCovered => statusCode == 409;

  /// Membership could not be verified right now; nothing was charged.
  bool get isUnavailable => statusCode == 503;

  @override
  String toString() => message;
}

/// The app's client for membership on `apps/api`.
///
/// Membership is verified against 24SevenOffice on the server; the app only
/// asks. Purchases use the same trusted checkout as the website, marked
/// `client: "app"` so the payment provider returns the student to the app.
class MembershipApiClient {
  MembershipApiClient({http.Client? httpClient, ApiJwtProvider? jwtProvider})
    : _httpClient = httpClient,
      _jwtProvider = jwtProvider ?? appwriteJwt;

  final http.Client? _httpClient;
  final ApiJwtProvider _jwtProvider;

  static const Duration _timeout = Duration(seconds: 20);

  /// The student's membership overview. [refresh] asks the server to re-check
  /// 24SevenOffice now (it does so at most once a minute).
  Future<MembershipOverview> fetchOverview({bool refresh = false}) async {
    final data = await _send(
      'GET',
      apiUri('/api/membership', refresh ? {'refresh': '1'} : null),
    );
    return MembershipOverview.fromJson(data);
  }

  /// Creates the membership order and payment session.
  Future<StartedCheckout> startCheckout({
    required PaymentProvider provider,
    required String planId,
    required String campusId,
  }) async {
    final data = await _send(
      'POST',
      apiUri('/api/payment/${provider.id}/membership-checkout'),
      body: {'campusId': campusId, 'client': 'app', 'planId': planId},
    );
    final checkoutUrl = data['checkoutUrl']?.toString() ?? '';
    final orderId = data['orderId']?.toString() ?? '';
    if (checkoutUrl.isEmpty || orderId.isEmpty) {
      throw const MembershipApiException('The payment could not be started.');
    }
    return StartedCheckout(checkoutUrl: checkoutUrl, orderId: orderId);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    final client = _httpClient ?? http.Client();
    final shouldClose = _httpClient == null;
    try {
      final jwt = await _jwtProvider();
      final request = http.Request(method, uri)
        ..headers.addAll({
          if (body != null) 'content-type': 'application/json',
          if (jwt != null) 'Authorization': 'Bearer $jwt',
        });
      if (body != null) {
        request.body = jsonEncode(body);
      }
      final response = await http.Response.fromStream(
        await client.send(request).timeout(_timeout),
      );

      Map<String, dynamic> map;
      try {
        final decoded = jsonDecode(response.body);
        map = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      } catch (_) {
        map = <String, dynamic>{};
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MembershipApiException(
          (map['message'] ?? map['error'] ?? 'Something went wrong.')
              .toString(),
          statusCode: response.statusCode,
        );
      }
      return map;
    } finally {
      if (shouldClose) client.close();
    }
  }
}
