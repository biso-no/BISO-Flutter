import 'dart:async';
import 'dart:convert';
import 'dart:io' show IOException;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/member_pass.dart';
import 'api_auth.dart';

/// The member pass endpoints on `apps/api`. The server signs every code and
/// decides every answer; the app only asks.
abstract interface class MemberPassApi {
  Future<MemberPassResponse> fetchPass();
  Future<Uint8List> fetchApplePass();
  Future<Uri> fetchGoogleSaveUrl();
  Future<ScannerAccess> fetchScannerAccess();
  Future<ScanOutcome> scan(String code);
}

/// A member pass request that failed.
///
/// [error] is the server's `error` token, [network] when no answer came, or
/// `error` when the body held anything else. It never carries a body, a
/// header or a code, so it is safe to log.
class MemberPassApiException implements Exception {
  const MemberPassApiException(this.error, {this.statusCode});

  static const network = 'network';

  final String error;
  final int? statusCode;

  bool get isBadRequest => statusCode == 400;
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isRateLimited => statusCode == 429;
  bool get isNotConfigured => statusCode == 503;

  /// No answer, or a server-side failure worth trying again.
  bool get isTransient {
    final status = statusCode;
    return status == null || status >= 500;
  }

  @override
  String toString() => 'MemberPassApiException(${statusCode ?? '-'}, $error)';
}

class MemberPassApiClient implements MemberPassApi {
  MemberPassApiClient({
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

  @override
  Future<MemberPassResponse> fetchPass() async {
    final response = await _send('GET', '/api/member-pass');
    // Until apps/api deploys the route there is simply no pass to show.
    if (response.statusCode == 404) {
      return const NoPass(NoPassState.unavailable);
    }
    return MemberPassResponse.fromJson(_json(_ok(response)));
  }

  @override
  Future<Uint8List> fetchApplePass() async {
    final response = _ok(await _send('GET', '/api/member-pass/apple'));
    return response.bodyBytes;
  }

  @override
  Future<Uri> fetchGoogleSaveUrl() async {
    final response = _ok(await _send('GET', '/api/member-pass/google'));
    final url = Uri.tryParse('${_json(response)['saveUrl'] ?? ''}');
    if (url == null || url.scheme != 'https' || url.host.isEmpty) {
      throw const MemberPassApiException('invalid_response', statusCode: 502);
    }
    return url;
  }

  @override
  Future<ScannerAccess> fetchScannerAccess() async {
    final response = await _send('GET', '/api/member-pass/scanner');
    // Until apps/api deploys the route nobody is a scanner.
    if (response.statusCode == 404) {
      throw const MemberPassApiException('not_scanner', statusCode: 403);
    }
    return ScannerAccess.fromJson(_json(_ok(response)));
  }

  @override
  Future<ScanOutcome> scan(String code) async {
    final response = await _send(
      'POST',
      '/api/member-pass/scan',
      body: {'code': code},
    );
    return ScanOutcome.fromJson(_json(_ok(response)));
  }

  /// Sends the request, and once more with a new token when a token that
  /// was sent is refused: a reused token can expire or outlive its session.
  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final client = _httpClient ?? http.Client();
    final shouldClose = _httpClient == null;
    try {
      final jwt = await _jwtProvider();
      final response = await _sendOnce(client, method, path, body, jwt);
      if (response.statusCode != 401 || jwt == null) return response;
      _invalidateJwt();
      final fresh = await _jwtProvider();
      return await _sendOnce(client, method, path, body, fresh);
    } on TimeoutException {
      throw const MemberPassApiException(MemberPassApiException.network);
    } on http.ClientException {
      throw const MemberPassApiException(MemberPassApiException.network);
    } on IOException {
      throw const MemberPassApiException(MemberPassApiException.network);
    } finally {
      if (shouldClose) client.close();
    }
  }

  Future<http.Response> _sendOnce(
    http.Client client,
    String method,
    String path,
    Map<String, Object?>? body,
    String? jwt,
  ) async {
    final request = http.Request(method, apiUri(path))
      ..headers.addAll({
        'accept': 'application/json',
        if (body != null) 'content-type': 'application/json',
        if (jwt != null) 'Authorization': 'Bearer $jwt',
      });
    if (body != null) request.body = jsonEncode(body);
    return http.Response.fromStream(
      await client.send(request).timeout(_timeout),
    ).timeout(_timeout);
  }

  http.Response _ok(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    var error = 'error';
    try {
      final decoded = jsonDecode(response.body);
      final value = decoded is Map ? decoded['error'] : null;
      if (value is String && _safeError.hasMatch(value)) error = value;
    } catch (_) {
      // Not JSON: keep the generic token.
    }
    throw MemberPassApiException(error, statusCode: response.statusCode);
  }

  Map<String, dynamic> _json(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Fall through.
    }
    throw const MemberPassApiException('invalid_response', statusCode: 502);
  }
}
