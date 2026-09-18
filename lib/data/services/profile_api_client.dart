import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_auth.dart';

/// A profile save the server refused, with its message.
class ProfileApiException implements Exception {
  const ProfileApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Saves the signed-in person's own profile through `apps/api`.
///
/// Profile rows are read-only to their owner, so the app cannot write them
/// directly. The server keeps only self-service fields — name, contact and
/// bank details, avatar, bio, privacy, campus and interests — and drops
/// everything else. The student id and other BI link fields are set by the
/// BI link on biso.no, never through here.
class ProfileApiClient {
  ProfileApiClient({http.Client? httpClient, ApiJwtProvider? jwtProvider})
    : _httpClient = httpClient,
      _jwtProvider = jwtProvider ?? appwriteJwt;

  final http.Client? _httpClient;
  final ApiJwtProvider _jwtProvider;

  static const Duration _timeout = Duration(seconds: 20);
  static const String _fallbackMessage = 'We could not save your profile.';

  /// Writes [fields] (creating the profile if it does not exist yet) and
  /// returns the saved row.
  Future<Map<String, dynamic>> upsert(Map<String, dynamic> fields) async {
    final client = _httpClient ?? http.Client();
    final shouldClose = _httpClient == null;
    try {
      final jwt = await _jwtProvider();
      final response = await client
          .put(
            apiUri('/api/profile'),
            headers: {
              'content-type': 'application/json',
              if (jwt != null) 'Authorization': 'Bearer $jwt',
            },
            body: jsonEncode(fields),
          )
          .timeout(_timeout);

      Map<String, dynamic> body;
      try {
        final decoded = jsonDecode(response.body);
        body = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      } catch (_) {
        body = <String, dynamic>{};
      }

      final ok = response.statusCode >= 200 && response.statusCode < 300;
      final profile = body['profile'];
      if (!ok || body['success'] != true || profile is! Map<String, dynamic>) {
        throw ProfileApiException(
          (body['error'] ?? _fallbackMessage).toString(),
          statusCode: response.statusCode,
        );
      }
      return profile;
    } finally {
      if (shouldClose) client.close();
    }
  }
}
