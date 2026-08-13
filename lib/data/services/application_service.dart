import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/content_locale.dart';
import '../models/application_model.dart';
import '../models/job_model.dart';
import 'appwrite_service.dart';

class ApplicationException implements Exception {
  final String message;
  final int? statusCode;

  const ApplicationException(this.message, {this.statusCode});

  bool get isDuplicate => statusCode == 409;

  @override
  String toString() => message;
}

/// One answer keyed to a vacancy custom question, ready for submission.
class ApplicationAnswerInput {
  final JobQuestionModel question;
  final String answer;

  const ApplicationAnswerInput({required this.question, required this.answer});
}

/// Submits applications to and reads application status from the BISO Sites
/// API (JWT-authenticated with the caller's Appwrite session).
class ApplicationService {
  Future<String> submitApplication({
    required String jobId,
    required String applicantName,
    String? applicantPhone,
    String? coverLetter,
    List<String> availability = const [],
    String? linkedinUrl,
    String? currentRole,
    String? currentEmployer,
    List<ApplicationAnswerInput> answers = const [],
    File? resume,
    required bool gdprConsent,
  }) async {
    final uri = _apiUri('/api/jobs/$jobId/apply');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(await _authHeaders());

    request.fields['applicant_name'] = applicantName;
    request.fields['gdpr_consent'] = gdprConsent ? 'true' : 'false';
    if (applicantPhone != null && applicantPhone.trim().isNotEmpty) {
      request.fields['applicant_phone'] = applicantPhone.trim();
    }
    if (coverLetter != null && coverLetter.trim().isNotEmpty) {
      request.fields['cover_letter'] = coverLetter.trim();
    }
    if (linkedinUrl != null && linkedinUrl.trim().isNotEmpty) {
      request.fields['linkedin_url'] = linkedinUrl.trim();
    }
    if (currentRole != null && currentRole.trim().isNotEmpty) {
      request.fields['current_role'] = currentRole.trim();
    }
    if (currentEmployer != null && currentEmployer.trim().isNotEmpty) {
      request.fields['current_employer'] = currentEmployer.trim();
    }
    if (availability.isNotEmpty) {
      request.fields['availability'] = availability.join('\n');
    }
    for (final entry in answers) {
      request.fields['answer.${entry.question.id}'] = entry.answer;
      request.fields['answer_type.${entry.question.id}'] = entry.question.type;
      request.fields['answer_label.${entry.question.id}'] =
          entry.question.label;
    }
    if (resume != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'resume',
          resume.path,
          contentType: MediaType.parse(
            lookupMimeType(resume.path) ?? 'application/pdf',
          ),
        ),
      );
    }

    AppLogger.api(
      'Submitting job application',
      endpoint: uri.toString(),
      method: 'POST',
      extra: {
        'job_id': jobId,
        'answer_count': answers.length,
        'has_resume': resume != null,
      },
    );

    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final body = await streamed.stream.bytesToString();
    final data = _decodeResponse(body, streamed.statusCode);
    return (data['application_id'] ?? '').toString();
  }

  Future<List<ApplicationModel>> getMyApplications() async {
    final locale = await ContentLocale.current();
    final uri = _apiUri('/api/applications', {'locale': locale});

    final response = await http.get(uri, headers: await _authHeaders());
    final data = _decodeResponse(response.body, response.statusCode);

    final applications =
        (data['applications'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(ApplicationModel.fromMap)
            .toList(growable: false);

    AppLogger.info(
      '[APPLICATIONS] Loaded my applications',
      extra: {'count': applications.length},
    );
    return applications;
  }

  Future<Map<String, String>> _authHeaders() async {
    final jwt = await account.createJWT();
    return {'Authorization': 'Bearer ${jwt.jwt}'};
  }

  Uri _apiUri(String path, [Map<String, String>? queryParameters]) {
    final base = AppConstants.apiBaseUrl.endsWith('/')
        ? AppConstants.apiBaseUrl.substring(
            0,
            AppConstants.apiBaseUrl.length - 1,
          )
        : AppConstants.apiBaseUrl;
    return Uri.parse('$base$path').replace(
      queryParameters: queryParameters == null || queryParameters.isEmpty
          ? null
          : queryParameters,
    );
  }

  Map<String, dynamic> _decodeResponse(String body, int statusCode) {
    final decoded = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
    final map = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'data': decoded};
    if (statusCode < 200 || statusCode >= 300 || map['success'] == false) {
      throw ApplicationException(
        (map['error'] ?? map['message'] ?? 'Application request failed')
            .toString(),
        statusCode: statusCode,
      );
    }
    return map;
  }
}
