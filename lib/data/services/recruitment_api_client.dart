import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/job_application.dart';
import 'api_auth.dart';

/// Listing applications failed; [message] is the server's when it sent one.
class RecruitmentApiException implements Exception {
  const RecruitmentApiException(this.code, this.message, {this.statusCode});

  final ApplicationError code;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Applies for vacancies and lists the student's applications through
/// `apps/api` (`/api/recruitment/applications`), the same flow and field
/// names as the website's apply form.
///
/// Applications are written with the server's key: the student has no write
/// access to `job_applications` or the `resumes` bucket. The server takes the
/// applicant's email from the account, never from the form.
class RecruitmentApiClient {
  RecruitmentApiClient({http.Client? httpClient, ApiJwtProvider? jwtProvider})
    : _httpClient = httpClient,
      _jwtProvider = jwtProvider ?? appwriteJwt;

  final http.Client? _httpClient;
  final ApiJwtProvider _jwtProvider;

  static const String _path = '/api/recruitment/applications';

  /// Two PDFs of up to 5 MB each over a phone connection.
  static const Duration _submitTimeout = Duration(seconds: 90);
  static const Duration _listTimeout = Duration(seconds: 20);
  static const String _submitFallback =
      'We could not send your application. Please try again.';
  static const String _listFallback = 'Failed to load applications';

  /// Never throws: every outcome is a [ApplicationSubmitResult].
  Future<ApplicationSubmitResult> submit(JobApplicationDraft draft) async {
    final client = _httpClient ?? http.Client();
    final shouldClose = _httpClient == null;
    try {
      final request = http.MultipartRequest('POST', apiUri(_path))
        ..headers.addAll(await _authHeaders())
        ..fields.addAll(_fields(draft));
      request.files.add(await _pdf('cover_letter', draft.coverLetter));
      final resume = draft.resume;
      if (resume != null) request.files.add(await _pdf('resume', resume));

      final streamed = await client.send(request).timeout(_submitTimeout);
      final response = await http.Response.fromStream(streamed);
      final body = _decode(response.body);

      if (response.statusCode == 201 && body['success'] == true) {
        return ApplicationSubmitResult.submitted(
          (body['applicationId'] ?? '').toString(),
        );
      }
      final serverMessage = body['error'];
      if (response.statusCode == 401) {
        return ApplicationSubmitResult.rejected(
          ApplicationError.notAuthenticated,
          serverMessage is String ? serverMessage : 'Authentication required',
        );
      }
      return ApplicationSubmitResult.rejected(
        ApplicationError.fromCode(body['code']?.toString()),
        serverMessage is String ? serverMessage : _submitFallback,
      );
    } on Exception {
      // No answer, or none in time. The application may still have arrived;
      // sending it again is safe, the server answers `already_applied`.
      return const ApplicationSubmitResult.rejected(
        ApplicationError.network,
        _submitFallback,
      );
    } finally {
      if (shouldClose) client.close();
    }
  }

  /// The student's applications, newest first.
  Future<List<MyApplication>> listMine() async {
    final client = _httpClient ?? http.Client();
    final shouldClose = _httpClient == null;
    try {
      final response = await client
          .get(apiUri(_path), headers: await _authHeaders())
          .timeout(_listTimeout);
      final body = _decode(response.body);
      final applications = body['applications'];
      if (response.statusCode == 200 && applications is List) {
        return [
          for (final application in applications.whereType<Map>())
            MyApplication.fromJson(Map<String, dynamic>.from(application)),
        ];
      }
      final serverMessage = body['error'];
      throw RecruitmentApiException(
        response.statusCode == 401
            ? ApplicationError.notAuthenticated
            : ApplicationError.submitFailed,
        serverMessage is String ? serverMessage : _listFallback,
        statusCode: response.statusCode,
      );
    } finally {
      if (shouldClose) client.close();
    }
  }

  static Map<String, String> _fields(JobApplicationDraft draft) => {
    'job_id': draft.jobId,
    'applicant_name': draft.applicantName,
    'applicant_phone': draft.applicantPhone,
    'linkedin_url': draft.linkedinUrl,
    'current_role': draft.currentRole,
    'current_employer': draft.currentEmployer,
    'availability': draft.availability,
    'gdpr_consent': 'true',
    for (final question in draft.questions) ...{
      'answer.${question.id}': draft.formValue(question),
      'answer_label.${question.id}': question.label,
      'answer_type.${question.id}': question.type.wireName,
    },
  };

  /// The server reads each part's own Content-Type and refuses anything but
  /// `application/pdf` with `invalid_file`.
  static Future<http.MultipartFile> _pdf(
    String field,
    ApplicationDocument document,
  ) async {
    final contentType = MediaType('application', 'pdf');
    final bytes = document.bytes;
    if (bytes != null) {
      return http.MultipartFile.fromBytes(
        field,
        bytes,
        filename: document.name,
        contentType: contentType,
      );
    }
    return http.MultipartFile.fromPath(
      field,
      document.path!,
      filename: document.name,
      contentType: contentType,
    );
  }

  Future<Map<String, String>> _authHeaders() async {
    final jwt = await _jwtProvider();
    return jwt == null ? const {} : {'Authorization': 'Bearer $jwt'};
  }

  static Map<String, dynamic> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }
}
