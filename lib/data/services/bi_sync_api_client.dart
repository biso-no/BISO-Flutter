import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_auth.dart';

/// Why `POST /api/auth/bi-sync` did not confirm a student number.
enum BiSyncError {
  /// The account has no BI sign-in; the student signs in with BI first.
  noBiIdentity,

  /// The BI account is not a student account (no `s…@bi.no` address).
  invalidBiEmail,

  /// The student number was saved, but BI's directory could not be read for
  /// the rest. The student counts as linked.
  directoryUnavailable,

  /// The student number already belongs to another BISO account.
  alreadyLinked,

  /// Anything else, including a network or server failure.
  syncFailed,

  /// The server saw no session.
  notAuthenticated;

  static BiSyncError fromCode(Object? code) => switch (code) {
    'no_bi_identity' => noBiIdentity,
    'invalid_bi_email' => invalidBiEmail,
    'directory_unavailable' => directoryUnavailable,
    'already_linked' => alreadyLinked,
    'not_authenticated' => notAuthenticated,
    _ => syncFailed,
  };
}

/// What the server's BI sync answered.
class BiSyncResult {
  const BiSyncResult({
    required this.success,
    this.studentId,
    this.campusHint,
    this.error,
  });

  const BiSyncResult.failed(BiSyncError this.error)
    : success = false,
      studentId = null,
      campusHint = null;

  final bool success;
  final String? studentId;
  final String? campusHint;
  final BiSyncError? error;
}

/// Asks `apps/api` to copy the signed-in student's number from their BI
/// sign-in onto their profile.
///
/// `student_id` and the `bi_*` columns are server-written only. The server
/// reads them from the account's own BI (Appwrite OIDC) identity, so the app
/// sends nothing but its session.
class BiSyncApiClient {
  BiSyncApiClient({http.Client? httpClient, ApiJwtProvider? jwtProvider})
    : _httpClient = httpClient,
      _jwtProvider = jwtProvider ?? appwriteJwt;

  final http.Client? _httpClient;
  final ApiJwtProvider _jwtProvider;

  static const Duration _timeout = Duration(seconds: 20);

  /// Never throws: a refusal, a server error or a network failure each come
  /// back as a [BiSyncResult] with its [BiSyncError].
  Future<BiSyncResult> sync() async {
    final client = _httpClient ?? http.Client();
    final shouldClose = _httpClient == null;
    try {
      final jwt = await _jwtProvider();
      final response = await client
          .post(
            apiUri('/api/auth/bi-sync'),
            headers: {if (jwt != null) 'Authorization': 'Bearer $jwt'},
          )
          .timeout(_timeout);

      if (response.statusCode == 401) {
        return const BiSyncResult.failed(BiSyncError.notAuthenticated);
      }
      if (response.statusCode != 200) {
        return const BiSyncResult.failed(BiSyncError.syncFailed);
      }
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        return const BiSyncResult.failed(BiSyncError.syncFailed);
      }
      if (body['success'] != true) {
        return BiSyncResult.failed(BiSyncError.fromCode(body['error']));
      }
      final studentId = body['studentId'];
      final campusHint = body['campusHint'];
      return BiSyncResult(
        success: true,
        studentId: studentId is String ? studentId : null,
        campusHint: campusHint is String ? campusHint : null,
      );
    } catch (_) {
      return const BiSyncResult.failed(BiSyncError.syncFailed);
    } finally {
      if (shouldClose) client.close();
    }
  }
}
