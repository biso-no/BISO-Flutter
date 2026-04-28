import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import '../../core/constants/app_constants.dart';
import '../models/expense_v2_models.dart';
import 'appwrite_service.dart';

class ExpenseApiException implements Exception {
  final String message;
  final int? statusCode;

  const ExpenseApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ExpenseApiClient {
  ExpenseApiClient({http.Client? httpClient}) : _httpClient = httpClient;

  final http.Client? _httpClient;

  Future<ExpenseUploadedFile> uploadExpenseAttachment(File file) async {
    final mimeType = detectExpenseMimeType(file.path);
    final created = await storage.createFile(
      bucketId: AppConstants.expensesBucketId,
      fileId: ID.unique(),
      file: InputFile.fromPath(
        path: file.path,
        filename: file.uri.pathSegments.isNotEmpty
            ? file.uri.pathSegments.last
            : null,
      ),
    );
    return ExpenseUploadedFile(
      fileId: created.$id,
      viewUrl: _publicFileUrl(AppConstants.expensesBucketId, created.$id),
      mimeType: mimeType,
      fileName: created.name,
    );
  }

  Future<ExpenseOcrResult> runOcr(File file, {String? purpose}) async {
    final uri = _apiUri('/api/expenses/ocr', {
      if (purpose != null && purpose.isNotEmpty) 'purpose': purpose,
    });
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(await _authHeaders());
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: MediaType.parse(detectExpenseMimeType(file.path)),
      ),
    );

    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final body = await streamed.stream.bytesToString();
    final data = _decodeResponse(body, streamed.statusCode);
    return ExpenseOcrResult.fromMap(data);
  }

  Future<String> summarize({
    required ExpenseAssignment assignment,
    required List<ExpenseReceiptDraft> receipts,
  }) async {
    final payload = ExpensePayloadBuilder.buildSummaryPayload(
      assignment: assignment,
      receipts: receipts,
    );
    final data = await _postJson('/api/expenses/summary', payload);
    return (data['summary'] ?? '').toString();
  }

  Future<ExpenseDraftResult> saveDraft(Map<String, dynamic> payload) async {
    final data = await _postJson('/api/expenses/draft', payload);
    return ExpenseDraftResult.fromMap(data);
  }

  Future<ExpenseSubmitResult> submit(Map<String, dynamic> payload) async {
    final data = await _postJson('/api/expenses/submit', payload);
    return ExpenseSubmitResult.fromMap(data);
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final client = _httpClient ?? http.Client();
    final shouldClose = _httpClient == null;
    try {
      final response = await client.post(
        _apiUri(path),
        headers: {...await _authHeaders(), 'content-type': 'application/json'},
        body: jsonEncode(payload),
      );
      return _decodeResponse(response.body, response.statusCode);
    } finally {
      if (shouldClose) client.close();
    }
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
      throw ExpenseApiException(
        (map['error'] ?? map['message'] ?? 'Expense API request failed')
            .toString(),
        statusCode: statusCode,
      );
    }
    return map;
  }

  String _publicFileUrl(String bucketId, String fileId) {
    return '${AppConstants.appwriteEndpoint}/storage/buckets/$bucketId/files/$fileId/view?project=${AppConstants.appwriteProjectId}';
  }
}

String detectExpenseMimeType(String path) {
  final detected = lookupMimeType(path);
  if (detected != null) return detected;
  final lower = path.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.heic')) return 'image/heic';
  return 'application/octet-stream';
}
