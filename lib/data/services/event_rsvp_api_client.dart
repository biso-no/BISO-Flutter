import 'dart:async';
import 'dart:convert';
import 'dart:io' show IOException;

import 'package:http/http.dart' as http;

import '../models/event_rsvp.dart';
import 'api_auth.dart';

/// The event RSVP endpoint on `apps/api`. The server decides who may answer
/// and whether answers are still open; the app only asks.
abstract interface class EventRsvpApi {
  /// Counts for [eventId]. When [signedIn], the caller's own answer is
  /// included.
  Future<EventRsvpSummary> fetch(String eventId, {required bool signedIn});

  /// Saves the caller's answer; `null` clears it.
  Future<EventRsvpSummary> respond(String eventId, EventRsvpStatus? status);
}

enum EventRsvpApiErrorKind {
  /// The route does not exist yet (old API).
  notDeployed,
  notAuthenticated,
  invalidRequest,
  notFound,
  membersOnly,
  closed,
  rateLimited,
  unavailable,
  network,
  unknown,
}

/// An RSVP request that failed. It never carries a body or a header, so it
/// is safe to log.
class EventRsvpApiException implements Exception {
  const EventRsvpApiException(this.kind, {this.statusCode});

  final EventRsvpApiErrorKind kind;
  final int? statusCode;

  @override
  String toString() =>
      'EventRsvpApiException(${statusCode ?? '-'}, ${kind.name})';
}

class EventRsvpApiClient implements EventRsvpApi {
  EventRsvpApiClient({
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

  static const Map<String, EventRsvpApiErrorKind> _tokens = {
    'invalid_request': EventRsvpApiErrorKind.invalidRequest,
    'not_authenticated': EventRsvpApiErrorKind.notAuthenticated,
    'members_only': EventRsvpApiErrorKind.membersOnly,
    'not_found': EventRsvpApiErrorKind.notFound,
    'closed': EventRsvpApiErrorKind.closed,
    'rate_limited': EventRsvpApiErrorKind.rateLimited,
    'unavailable': EventRsvpApiErrorKind.unavailable,
  };

  @override
  Future<EventRsvpSummary> fetch(
    String eventId, {
    required bool signedIn,
  }) async {
    final response = await _send(
      'GET',
      _path(eventId),
      authenticated: signedIn,
    );
    return _summary(response);
  }

  @override
  Future<EventRsvpSummary> respond(
    String eventId,
    EventRsvpStatus? status,
  ) async {
    final response = await _send(
      'POST',
      _path(eventId),
      body: jsonEncode({'status': status?.wire}),
    );
    return _summary(response);
  }

  String _path(String eventId) =>
      '/api/events/${Uri.encodeComponent(eventId)}/rsvp';

  EventRsvpSummary _summary(http.Response response) {
    if (_isOk(response)) {
      final summary = EventRsvpSummary.tryParse(_json(response));
      if (summary == null) {
        throw const EventRsvpApiException(
          EventRsvpApiErrorKind.unknown,
          statusCode: 502,
        );
      }
      return summary;
    }
    final token = _token(response);
    // No error token means the route is not there (yet).
    if (response.statusCode == 404 && token == null) {
      throw const EventRsvpApiException(
        EventRsvpApiErrorKind.notDeployed,
        statusCode: 404,
      );
    }
    throw _failure(response, token);
  }

  /// Sends the request, and once more with a new token when a token that
  /// was sent is refused: a reused token can expire or outlive its session.
  /// An unauthenticated request carries no token and is never retried.
  Future<http.Response> _send(
    String method,
    String path, {
    String? body,
    bool authenticated = true,
  }) async {
    final client = _httpClient ?? http.Client();
    final shouldClose = _httpClient == null;
    try {
      final jwt = authenticated ? await _jwtProvider() : null;
      final response = await _sendOnce(client, method, path, body, jwt);
      if (response.statusCode != 401 || jwt == null) return response;
      _invalidateJwt();
      final fresh = await _jwtProvider();
      return await _sendOnce(client, method, path, body, fresh);
    } on TimeoutException {
      throw const EventRsvpApiException(EventRsvpApiErrorKind.network);
    } on http.ClientException {
      throw const EventRsvpApiException(EventRsvpApiErrorKind.network);
    } on IOException {
      throw const EventRsvpApiException(EventRsvpApiErrorKind.network);
    } finally {
      if (shouldClose) client.close();
    }
  }

  Future<http.Response> _sendOnce(
    http.Client client,
    String method,
    String path,
    String? body,
    String? jwt,
  ) async {
    final request = http.Request(method, apiUri(path))
      ..headers.addAll({
        'accept': 'application/json',
        if (body != null) 'content-type': 'application/json',
        if (jwt != null) 'Authorization': 'Bearer $jwt',
      });
    if (body != null) request.body = body;
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

  EventRsvpApiException _failure(http.Response response, String? token) {
    final status = response.statusCode;
    final kind =
        _tokens[token] ??
        switch (status) {
          401 => EventRsvpApiErrorKind.notAuthenticated,
          404 => EventRsvpApiErrorKind.notFound,
          _ => EventRsvpApiErrorKind.unknown,
        };
    return EventRsvpApiException(kind, statusCode: status);
  }

  Map<String, dynamic> _json(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Fall through.
    }
    throw const EventRsvpApiException(
      EventRsvpApiErrorKind.unknown,
      statusCode: 502,
    );
  }
}
