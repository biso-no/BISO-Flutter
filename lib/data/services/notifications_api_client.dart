import 'dart:async';
import 'dart:convert';
import 'dart:io' show IOException;

import 'package:http/http.dart' as http;

import 'api_auth.dart';

/// The most announcement ids one request may carry; the server refuses more.
const int kNotificationsApiBatchSize = 100;

/// The inbox state endpoints on `apps/api`. The `user_notifications` table
/// gives the app no write access, so read and cleared state is saved here.
abstract interface class NotificationsApi {
  /// Saves [announcementIds] (at most [kNotificationsApiBatchSize]) as read
  /// for the signed-in student.
  Future<void> markRead(List<String> announcementIds);

  /// Clears [announcementIds] (at most [kNotificationsApiBatchSize]) from the
  /// signed-in student's inbox on every device, which also counts them read.
  Future<void> clear(List<String> announcementIds);
}

enum NotificationsApiErrorKind {
  /// The routes do not exist yet (old API).
  notDeployed,
  notAuthenticated,
  invalidRequest,
  rateLimited,
  unavailable,
  network,
  unknown,
}

/// An inbox state request that failed. It never carries a body, an id or a
/// token, so it is safe to log.
class NotificationsApiException implements Exception {
  const NotificationsApiException(this.kind, {this.statusCode});

  final NotificationsApiErrorKind kind;
  final int? statusCode;

  @override
  String toString() =>
      'NotificationsApiException(${statusCode ?? '-'}, ${kind.name})';
}

class NotificationsApiClient implements NotificationsApi {
  NotificationsApiClient({
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

  static const Map<String, NotificationsApiErrorKind> _tokens = {
    'not_authenticated': NotificationsApiErrorKind.notAuthenticated,
    'invalid_request': NotificationsApiErrorKind.invalidRequest,
    'rate_limited': NotificationsApiErrorKind.rateLimited,
    'unavailable': NotificationsApiErrorKind.unavailable,
  };

  @override
  Future<void> markRead(List<String> announcementIds) =>
      _post('/api/notifications/read', announcementIds);

  @override
  Future<void> clear(List<String> announcementIds) =>
      _post('/api/notifications/clear', announcementIds);

  Future<void> _post(String path, List<String> announcementIds) async {
    if (announcementIds.length > kNotificationsApiBatchSize) {
      throw ArgumentError.value(
        announcementIds.length,
        'announcementIds',
        'at most $kNotificationsApiBatchSize per request',
      );
    }
    if (announcementIds.isEmpty) return;

    final body = jsonEncode({'announcementIds': announcementIds});
    final response = await _send(path, body);
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    final token = _token(response);
    // No error token means the route is not there (yet).
    if (response.statusCode == 404 && token == null) {
      throw const NotificationsApiException(
        NotificationsApiErrorKind.notDeployed,
        statusCode: 404,
      );
    }
    throw _failure(response, token);
  }

  /// Sends the request, and once more with a new token when a token that
  /// was sent is refused: a reused token can expire or outlive its session.
  Future<http.Response> _send(String path, String body) async {
    final client = _httpClient ?? http.Client();
    final shouldClose = _httpClient == null;
    try {
      final jwt = await _jwtProvider();
      final response = await _sendOnce(client, path, body, jwt);
      if (response.statusCode != 401 || jwt == null) return response;
      _invalidateJwt();
      final fresh = await _jwtProvider();
      return await _sendOnce(client, path, body, fresh);
    } on TimeoutException {
      throw const NotificationsApiException(NotificationsApiErrorKind.network);
    } on http.ClientException {
      throw const NotificationsApiException(NotificationsApiErrorKind.network);
    } on IOException {
      throw const NotificationsApiException(NotificationsApiErrorKind.network);
    } finally {
      if (shouldClose) client.close();
    }
  }

  Future<http.Response> _sendOnce(
    http.Client client,
    String path,
    String body,
    String? jwt,
  ) async {
    final request = http.Request('POST', apiUri(path))
      ..headers.addAll({
        'accept': 'application/json',
        'content-type': 'application/json',
        if (jwt != null) 'Authorization': 'Bearer $jwt',
      })
      ..body = body;
    return http.Response.fromStream(
      await client.send(request).timeout(_timeout),
    ).timeout(_timeout);
  }

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

  NotificationsApiException _failure(http.Response response, String? token) {
    final status = response.statusCode;
    final kind =
        _tokens[token] ??
        switch (status) {
          401 => NotificationsApiErrorKind.notAuthenticated,
          429 => NotificationsApiErrorKind.rateLimited,
          _ => NotificationsApiErrorKind.unknown,
        };
    return NotificationsApiException(kind, statusCode: status);
  }
}
