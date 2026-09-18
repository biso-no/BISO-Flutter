import 'dart:convert';
import 'dart:io';

import 'package:biso/data/services/expense_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late http.Request sent;
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('expense_api_client_test');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  ExpenseApiClient clientReturning(
    http.Response response, {
    String? jwt = 'jwt-1',
  }) {
    return ExpenseApiClient(
      httpClient: MockClient((request) async {
        sent = request;
        return response;
      }),
      jwtProvider: () async => jwt,
    );
  }

  File pngReceipt() {
    final file = File('${tempDir.path}/receipt.png');
    file.writeAsBytesSync([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    return file;
  }

  test(
    'uploads a receipt to the attachments route and reads the stored file',
    () async {
      final client = clientReturning(
        http.Response(
          jsonEncode({
            'success': true,
            'file': {
              'fileId': 'file-1',
              'mimeType': 'image/png',
              'name': 'receipt.png',
              'size': 8,
              'viewUrl':
                  'https://appwrite.biso.no/v1/storage/buckets/expenses/files/file-1/view?project=biso',
            },
          }),
          201,
        ),
      );

      final uploaded = await client.uploadExpenseAttachment(pngReceipt());

      expect(sent.method, 'POST');
      expect(
        sent.url.toString(),
        'https://api.biso.no/api/expenses/attachments',
      );
      expect(sent.headers['Authorization'], 'Bearer jwt-1');
      expect(sent.headers['content-type'], startsWith('multipart/form-data'));
      expect(
        utf8.decode(sent.bodyBytes, allowMalformed: true),
        contains('filename="receipt.png"'),
      );
      expect(uploaded.fileId, 'file-1');
      expect(uploaded.fileName, 'receipt.png');
      expect(uploaded.mimeType, 'image/png');
      expect(uploaded.viewUrl, contains('/files/file-1/view'));
    },
  );

  test("shows the server's reason when a receipt is refused", () async {
    final client = clientReturning(
      http.Response(
        jsonEncode({
          'success': false,
          'error':
              'Unsupported file type. Please upload a PDF, PNG, or JPEG file.',
        }),
        415,
      ),
    );

    await expectLater(
      client.uploadExpenseAttachment(pngReceipt()),
      throwsA(
        isA<ExpenseApiException>()
            .having((e) => e.statusCode, 'statusCode', 415)
            .having((e) => e.message, 'message', contains('PDF, PNG, or JPEG')),
      ),
    );
  });

  test('deletes a draft through the draft route', () async {
    final client = clientReturning(
      http.Response(jsonEncode({'success': true}), 200),
    );

    await client.deleteDraft('expense-1');

    expect(sent.method, 'DELETE');
    expect(
      sent.url.toString(),
      'https://api.biso.no/api/expenses/draft?expenseId=expense-1',
    );
    expect(sent.headers['Authorization'], 'Bearer jwt-1');
  });

  test('refuses to report a submitted expense as deleted', () async {
    final client = clientReturning(
      http.Response(
        jsonEncode({
          'success': false,
          'error': 'Only draft expenses can be deleted',
        }),
        409,
      ),
    );

    await expectLater(
      client.deleteDraft('expense-1'),
      throwsA(
        isA<ExpenseApiException>().having(
          (e) => e.message,
          'message',
          'Only draft expenses can be deleted',
        ),
      ),
    );
  });

  test('turns a non-JSON error page into a readable failure', () async {
    final client = clientReturning(http.Response('<html>502</html>', 502));

    await expectLater(
      client.deleteDraft('expense-1'),
      throwsA(isA<ExpenseApiException>()),
    );
  });

  test('sends no authorization header without a session', () async {
    final client = clientReturning(
      http.Response(
        jsonEncode({'success': false, 'error': 'Authentication required'}),
        401,
      ),
      jwt: null,
    );

    await expectLater(
      client.deleteDraft('expense-1'),
      throwsA(
        isA<ExpenseApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', 'Authentication required'),
      ),
    );
    expect(sent.headers.containsKey('Authorization'), isFalse);
  });
}
