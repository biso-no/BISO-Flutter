import 'dart:convert';
import 'dart:io';

import 'package:biso/data/services/bi_sync_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late http.Request sent;

  BiSyncApiClient clientReturning(http.Response response) {
    return BiSyncApiClient(
      httpClient: MockClient((request) async {
        sent = request;
        return response;
      }),
      jwtProvider: () async => 'jwt-1',
    );
  }

  http.Response json(Map<String, Object?> body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  test('posts with a bearer token and parses success', () async {
    final client = clientReturning(
      json({
        'success': true,
        'studentId': 's1234567',
        'hasEmployeeId': false,
        'campusHint': 'oslo',
      }),
    );

    final result = await client.sync();

    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'https://api.biso.no/api/auth/bi-sync');
    expect(sent.headers['Authorization'], 'Bearer jwt-1');
    expect(sent.body, isEmpty);
    expect(result.success, isTrue);
    expect(result.studentId, 's1234567');
    expect(result.campusHint, 'oslo');
    expect(result.error, isNull);
  });

  test('maps each error code', () async {
    const codes = {
      'no_bi_identity': BiSyncError.noBiIdentity,
      'invalid_bi_email': BiSyncError.invalidBiEmail,
      'directory_unavailable': BiSyncError.directoryUnavailable,
      'already_linked': BiSyncError.alreadyLinked,
      'sync_failed': BiSyncError.syncFailed,
      'not_authenticated': BiSyncError.notAuthenticated,
      'something_new': BiSyncError.syncFailed,
    };
    for (final MapEntry(key: code, value: error) in codes.entries) {
      final result = await clientReturning(
        json({'success': false, 'error': code}),
      ).sync();

      expect(result.success, isFalse, reason: code);
      expect(result.error, error, reason: code);
    }
  });

  test('a 500 is syncFailed', () async {
    final result = await clientReturning(
      http.Response('<html>500</html>', 500),
    ).sync();

    expect(result.success, isFalse);
    expect(result.error, BiSyncError.syncFailed);
  });

  test('a 401 is notAuthenticated', () async {
    final result = await clientReturning(
      json({'success': false, 'error': 'Authentication required'}, 401),
    ).sync();

    expect(result.error, BiSyncError.notAuthenticated);
  });

  test('a network failure is syncFailed', () async {
    final client = BiSyncApiClient(
      httpClient: MockClient(
        (_) async => throw const SocketException('offline'),
      ),
      jwtProvider: () async => 'jwt-1',
    );

    final result = await client.sync();

    expect(result.error, BiSyncError.syncFailed);
  });
}
