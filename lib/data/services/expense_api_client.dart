import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import '../models/expense_v2_models.dart';
import 'api_auth.dart';

class ExpenseApiException implements Exception {
  final String message;
  final int? statusCode;

  const ExpenseApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// The app's client for the reimbursement routes on `apps/api`.
///
/// Expense rows are read-only to the student and the `expenses` bucket has no
/// user create grant, so every write — receipts, drafts, submission, draft
/// deletion — goes through the API with the student's JWT.
class ExpenseApiClient {
  ExpenseApiClient({http.Client? httpClient, ApiJwtProvider? jwtProvider})
    : _httpClient = httpClient,
      _jwtProvider = jwtProvider ?? appwriteJwt;

  final http.Client? _httpClient;
  final ApiJwtProvider _jwtProvider;

  static const Duration _jsonTimeout = Duration(seconds: 20);

  /// Stores one receipt and returns the file the draft should reference.
  Future<ExpenseUploadedFile> uploadExpenseAttachment(File file) async {
    final request = http.MultipartRequest(
      'POST',
      apiUri('/api/expenses/attachments'),
    );
    request.headers.addAll(await _authHeaders());
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: MediaType.parse(detectExpenseMimeType(file.path)),
      ),
    );

    final response = await _sendMultipart(request, const Duration(seconds: 60));
    final data = _decodeResponse(response.body, response.statusCode);
    final stored = data['file'];
    if (stored is! Map || stored['fileId'] == null) {
      throw const ExpenseApiException('The receipt could not be stored.');
    }
    return ExpenseUploadedFile(
      fileId: stored['fileId'].toString(),
      viewUrl: (stored['viewUrl'] ?? '').toString(),
      mimeType: (stored['mimeType'] ?? detectExpenseMimeType(file.path))
          .toString(),
      fileName: (stored['name'] ?? '').toString(),
    );
  }

  Future<ExpenseOcrResult> runOcr(File file, {String? purpose}) async {
    final request = http.MultipartRequest(
      'POST',
      apiUri('/api/expenses/ocr', {
        if (purpose != null && purpose.isNotEmpty) 'purpose': purpose,
      }),
    );
    request.headers.addAll(await _authHeaders());
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: MediaType.parse(detectExpenseMimeType(file.path)),
      ),
    );

    final response = await _sendMultipart(request, const Duration(seconds: 30));
    final data = _decodeResponse(response.body, response.statusCode);
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

  /// Deletes one of the student's own drafts and the receipts it referenced.
  /// The server refuses anything that has left draft.
  Future<void> deleteDraft(String expenseId) async {
    final client = _httpClient ?? http.Client();
    final shouldClose = _httpClient == null;
    try {
      final response = await client
          .delete(
            apiUri('/api/expenses/draft', {'expenseId': expenseId}),
            headers: await _authHeaders(),
          )
          .timeout(_jsonTimeout);
      _decodeResponse(response.body, response.statusCode);
    } finally {
      if (shouldClose) client.close();
    }
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final client = _httpClient ?? http.Client();
    final shouldClose = _httpClient == null;
    try {
      final response = await client
          .post(
            apiUri(path),
            headers: {
              ...await _authHeaders(),
              'content-type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(_jsonTimeout);
      return _decodeResponse(response.body, response.statusCode);
    } finally {
      if (shouldClose) client.close();
    }
  }

  Future<http.Response> _sendMultipart(
    http.MultipartRequest request,
    Duration timeout,
  ) async {
    final client = _httpClient ?? http.Client();
    final shouldClose = _httpClient == null;
    try {
      final streamed = await client.send(request).timeout(timeout);
      return await http.Response.fromStream(streamed);
    } finally {
      if (shouldClose) client.close();
    }
  }

  Future<Map<String, String>> _authHeaders() async {
    final jwt = await _jwtProvider();
    return jwt == null ? const {} : {'Authorization': 'Bearer $jwt'};
  }

  Map<String, dynamic> _decodeResponse(String body, int statusCode) {
    Map<String, dynamic> map;
    try {
      final decoded = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
      map = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{'data': decoded};
    } catch (_) {
      map = <String, dynamic>{};
    }
    if (statusCode < 200 || statusCode >= 300 || map['success'] == false) {
      throw ExpenseApiException(
        (map['error'] ?? map['message'] ?? 'Expense API request failed')
            .toString(),
        statusCode: statusCode,
      );
    }
    return map;
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
