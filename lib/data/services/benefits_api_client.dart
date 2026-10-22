import 'dart:async';
import 'dart:convert';
import 'dart:io' show IOException;

import 'package:http/http.dart' as http;

import '../models/campus_benefit.dart';
import 'api_auth.dart';

/// The benefits endpoints on `apps/api`. The server decides who may see a
/// code; the app only asks.
abstract interface class BenefitsApi {
  Future<List<CampusBenefit>> fetchBenefits({String? campusId});

  /// The code or link for [benefitId]. Hand it to the caller and nothing
  /// else: it is never cached or logged.
  Future<String> reveal(String benefitId);
}

enum BenefitsApiErrorKind {
  /// The list route does not exist yet (old API).
  notDeployed,
  notAuthenticated,
  notMember,
  notFound,
  noCode,
  rateLimited,
  membershipUnavailable,
  unavailable,
  network,
  unknown,
}

/// A benefits request that failed. It never carries a body, a header or a
/// code, so it is safe to log.
class BenefitsApiException implements Exception {
  const BenefitsApiException(this.kind, {this.statusCode});

  final BenefitsApiErrorKind kind;
  final int? statusCode;

  @override
  String toString() =>
      'BenefitsApiException(${statusCode ?? '-'}, ${kind.name})';
}

class BenefitsApiClient implements BenefitsApi {
  BenefitsApiClient({
    http.Client? httpClient,
    ApiJwtProvider? jwtProvider,
    ApiJwtInvalidator? invalidateJwt,
  }) : _httpClient = httpClient,
       _jwtProvider = jwtProvider ?? appwriteJwt,
       _invalidateJwt = invalidateJwt ?? clearAppwriteJwtCache;

  final http.Client? _httpClient;
  final ApiJwtProvider _jwtProvider;
  final ApiJwtInvalidator _invalidateJwt;

  static const Duration _timeout = Duration(seconds: 20);
  static final RegExp _safeError = RegExp(r'^[a-z_]{1,40}$');

  static const Map<String, BenefitsApiErrorKind> _tokens = {
    'not_authenticated': BenefitsApiErrorKind.notAuthenticated,
    'not_member': BenefitsApiErrorKind.notMember,
    'not_found': BenefitsApiErrorKind.notFound,
    'no_code': BenefitsApiErrorKind.noCode,
    'rate_limited': BenefitsApiErrorKind.rateLimited,
    'membership_unavailable': BenefitsApiErrorKind.membershipUnavailable,
    'unavailable': BenefitsApiErrorKind.unavailable,
  };

  @override
  Future<List<CampusBenefit>> fetchBenefits({String? campusId}) async {
    final response = await _send(
      'GET',
      '/api/benefits',
      query: campusId == null ? null : {'campus': campusId},
    );
    if (_isOk(response)) {
      final list = _json(response)['benefits'];
      if (list is! List) {
        throw const BenefitsApiException(
          BenefitsApiErrorKind.unknown,
          statusCode: 502,
        );
      }
      return [for (final item in list) ?CampusBenefit.tryParse(item)];
    }
    final token = _token(response);
    // No error token means the route is not there (yet).
    if (response.statusCode == 404 && token == null) {
      throw const BenefitsApiException(
        BenefitsApiErrorKind.notDeployed,
        statusCode: 404,
      );
    }
    throw _failure(response, token);
  }

  @override
  Future<String> reveal(String benefitId) async {
    final response = await _send(
      'POST',
      '/api/benefits/${Uri.encodeComponent(benefitId)}/reveal',
    );
    if (!_isOk(response)) throw _failure(response, _token(response));
    final value = _json(response)['value'];
    if (value is! String || value.isEmpty) {
      throw const BenefitsApiException(
        BenefitsApiErrorKind.unknown,
        statusCode: 502,
      );
    }
    return value;
  }

  /// Sends the request, and once more with a new token when a token that
  /// was sent is refused: a reused token can expire or outlive its session.
  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? query,
  }) async {
    final client = _httpClient ?? http.Client();
    final shouldClose = _httpClient == null;
    try {
      final jwt = await _jwtProvider();
      final response = await _sendOnce(client, method, path, query, jwt);
      if (response.statusCode != 401 || jwt == null) return response;
      _invalidateJwt();
      final fresh = await _jwtProvider();
      return await _sendOnce(client, method, path, query, fresh);
    } on TimeoutException {
      throw const BenefitsApiException(BenefitsApiErrorKind.network);
    } on http.ClientException {
      throw const BenefitsApiException(BenefitsApiErrorKind.network);
    } on IOException {
      throw const BenefitsApiException(BenefitsApiErrorKind.network);
    } finally {
      if (shouldClose) client.close();
    }
  }

  Future<http.Response> _sendOnce(
    http.Client client,
    String method,
    String path,
    Map<String, String>? query,
    String? jwt,
  ) async {
    final request = http.Request(method, apiUri(path, query))
      ..headers.addAll({
        'accept': 'application/json',
        if (jwt != null) 'Authorization': 'Bearer $jwt',
      });
    return http.Response.fromStream(
      await client.send(request).timeout(_timeout),
    ).timeout(_timeout);
  }

  bool _isOk(http.Response response) =>
      response.statusCode >= 200 && response.statusCode < 300;

  /// The server's `error` token, when the body holds a valid one.
  String? _token(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      final value = decoded is Map ? decoded['error'] : null;
      if (value is String && _safeError.hasMatch(value)) return value;
    } catch (_) {
      // Not JSON: no token.
    }
    return null;
  }

  BenefitsApiException _failure(http.Response response, String? token) {
    final status = response.statusCode;
    final kind =
        _tokens[token] ??
        switch (status) {
          401 => BenefitsApiErrorKind.notAuthenticated,
          404 => BenefitsApiErrorKind.notFound,
          _ => BenefitsApiErrorKind.unknown,
        };
    return BenefitsApiException(kind, statusCode: status);
  }

  Map<String, dynamic> _json(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Fall through.
    }
    throw const BenefitsApiException(
      BenefitsApiErrorKind.unknown,
      statusCode: 502,
    );
  }
}
