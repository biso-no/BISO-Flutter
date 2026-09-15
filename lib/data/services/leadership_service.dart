import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../models/board_member_model.dart';

/// Board members come from `GET /api/campus/{campusId}/{departmentId}/board`
/// on the BISO API, which reads them from Azure AD.
///
/// `departmentId` is either a numeric `departments` row id or a literal Azure
/// department name. The server treats the segment `undefined` as "no
/// department" and answers with the campus's own management board, so the
/// campus-to-board mapping lives in one place: the server.
class LeadershipService {
  LeadershipService({http.Client? httpClient}) : _httpClient = httpClient;

  final http.Client? _httpClient;

  /// The route buffers every member's profile photo before it answers, so a
  /// large board can take a while.
  static const _timeout = Duration(seconds: 60);

  Future<BoardMembersResponse> getBoardMembers({
    required String campusId,
    String? departmentId,
  }) async {
    final client = _httpClient ?? http.Client();
    final shouldClose = _httpClient == null;
    try {
      final department = (departmentId == null || departmentId.isEmpty)
          ? 'undefined'
          : departmentId;
      final response = await client
          .get(_boardUri(campusId, department))
          .timeout(_timeout);

      final body = _decode(response.body);
      if (response.statusCode == 200 && body != null) {
        return BoardMembersResponse.fromMap(body);
      }
      return _failure(
        (body?['message'] ?? body?['error'] ?? 'HTTP ${response.statusCode}')
            .toString(),
      );
    } catch (e) {
      return _failure('Failed to fetch board members: $e');
    } finally {
      if (shouldClose) client.close();
    }
  }

  Uri _boardUri(String campusId, String departmentId) {
    final base = AppConstants.apiBaseUrl.endsWith('/')
        ? AppConstants.apiBaseUrl.substring(
            0,
            AppConstants.apiBaseUrl.length - 1,
          )
        : AppConstants.apiBaseUrl;
    return Uri.parse(
      '$base/api/campus/${Uri.encodeComponent(campusId)}/'
      '${Uri.encodeComponent(departmentId)}/board',
    );
  }

  Map<String, dynamic>? _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  BoardMembersResponse _failure(String error) => BoardMembersResponse(
    success: false,
    members: const [],
    count: 0,
    error: error,
  );
}
