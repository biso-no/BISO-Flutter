import 'dart:async';
import 'dart:convert';

import 'package:biso/data/models/member_pass.dart';
import 'package:biso/data/services/member_pass_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late http.Request sent;

  MemberPassApiClient clientReturning(http.Response response) {
    return MemberPassApiClient(
      httpClient: MockClient((request) async {
        sent = request;
        return response;
      }),
      jwtProvider: () async => 'jwt-secret-1',
    );
  }

  http.Response json(Object body, int status) =>
      http.Response(jsonEncode(body), status);

  Matcher failsWith(int? status, String error) => throwsA(
    isA<MemberPassApiException>()
        .having((e) => e.statusCode, 'statusCode', status)
        .having((e) => e.error, 'error', error),
  );

  group('fetchPass', () {
    test('sends the token and parses a no-pass state', () async {
      final client = clientReturning(json({'state': 'not_member'}, 200));
      final result = await client.fetchPass();
      expect(sent.method, 'GET');
      expect(sent.url.toString(), 'https://api.biso.no/api/member-pass');
      expect(sent.headers['Authorization'], 'Bearer jwt-secret-1');
      expect(result, const NoPass(NoPassState.notMember));
    });

    test('a 404 (route not deployed) reads as unavailable', () async {
      final client = clientReturning(http.Response('Not found', 404));
      expect(await client.fetchPass(), const NoPass(NoPassState.unavailable));
    });

    test('a 401 is unauthorized', () async {
      final client = clientReturning(json({'error': 'not_authenticated'}, 401));
      await expectLater(
        client.fetchPass(),
        failsWith(401, 'not_authenticated'),
      );
    });

    test('a 5xx is transient', () async {
      final client = clientReturning(http.Response('<html>', 502));
      await expectLater(
        client.fetchPass(),
        throwsA(
          isA<MemberPassApiException>().having(
            (e) => e.isTransient,
            'isTransient',
            isTrue,
          ),
        ),
      );
    });

    test('a network failure is transient with no status', () async {
      final client = MemberPassApiClient(
        httpClient: MockClient((_) async => throw http.ClientException('x')),
        jwtProvider: () async => 'jwt',
      );
      await expectLater(client.fetchPass(), failsWith(null, 'network'));
    });

    test('a timeout is a network failure', () async {
      final client = MemberPassApiClient(
        httpClient: MockClient((_) async => throw TimeoutException('slow')),
        jwtProvider: () async => 'jwt',
      );
      await expectLater(client.fetchPass(), failsWith(null, 'network'));
    });
  });

  group('wallets', () {
    test('returns the pkpass bytes', () async {
      final client = clientReturning(
        http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': 'application/vnd.apple.pkpass'},
        ),
      );
      expect(await client.fetchApplePass(), [1, 2, 3]);
      expect(sent.url.path, '/api/member-pass/apple');
    });

    test('apple 403, 404 and 500 keep their meaning', () async {
      await expectLater(
        clientReturning(json({'error': 'not_member'}, 403)).fetchApplePass(),
        failsWith(403, 'not_member'),
      );
      await expectLater(
        clientReturning(
          json({'error': 'not_configured'}, 404),
        ).fetchApplePass(),
        failsWith(404, 'not_configured'),
      );
      await expectLater(
        clientReturning(json({'error': 'failed'}, 500)).fetchApplePass(),
        failsWith(500, 'failed'),
      );
    });

    test('returns the Google save URL', () async {
      final client = clientReturning(
        json({'saveUrl': 'https://pay.google.com/gp/v/save/abc'}, 200),
      );
      expect(
        await client.fetchGoogleSaveUrl(),
        Uri.parse('https://pay.google.com/gp/v/save/abc'),
      );
      expect(sent.url.path, '/api/member-pass/google');
    });

    test('refuses a save URL that is not https', () async {
      final client = clientReturning(json({'saveUrl': 'javascript:x'}, 200));
      await expectLater(
        client.fetchGoogleSaveUrl(),
        failsWith(502, 'invalid_response'),
      );
    });

    test('google 404 and 502 keep their meaning', () async {
      await expectLater(
        clientReturning(
          json({'error': 'not_configured'}, 404),
        ).fetchGoogleSaveUrl(),
        failsWith(404, 'not_configured'),
      );
      await expectLater(
        clientReturning(
          json({'error': 'wallet_unavailable'}, 502),
        ).fetchGoogleSaveUrl(),
        failsWith(502, 'wallet_unavailable'),
      );
    });
  });

  group('scanner', () {
    test('parses access', () async {
      final client = clientReturning(
        json({
          'campusId': '1',
          'expiresAt': null,
          'dayColor': {'name': 'teal', 'hex': '#12A594'},
        }, 200),
      );
      final access = await client.fetchScannerAccess();
      expect(sent.url.path, '/api/member-pass/scanner');
      expect(access.campusId, '1');
    });

    test('a 404 (route not deployed) reads as not a scanner', () async {
      final client = clientReturning(http.Response('', 404));
      await expectLater(
        client.fetchScannerAccess(),
        failsWith(403, 'not_scanner'),
      );
    });

    test('503 is not configured', () async {
      final client = clientReturning(json({'error': 'not_configured'}, 503));
      await expectLater(
        client.fetchScannerAccess(),
        throwsA(
          isA<MemberPassApiException>().having(
            (e) => e.isNotConfigured,
            'isNotConfigured',
            isTrue,
          ),
        ),
      );
    });

    test('posts the scanned code as JSON', () async {
      final client = clientReturning(json({'result': 'valid'}, 200));
      final outcome = await client.scan('v1.u.1.sig');
      expect(sent.method, 'POST');
      expect(sent.url.path, '/api/member-pass/scan');
      expect(sent.headers['content-type'], startsWith('application/json'));
      expect(jsonDecode(sent.body), {'code': 'v1.u.1.sig'});
      expect(outcome.result, ScanResult.valid);
    });

    test('scan errors keep their status', () async {
      for (final (status, error) in [
        (400, 'invalid_body'),
        (401, 'not_authenticated'),
        (403, 'not_scanner'),
        (429, 'rate_limited'),
        (503, 'not_configured'),
      ]) {
        await expectLater(
          clientReturning(json({'error': error}, status)).scan('x'),
          failsWith(status, error),
        );
      }
    });
  });

  test('exceptions never carry a code, token or body', () async {
    final client = clientReturning(
      json({'error': 'v1.user.1.SIG jwt-secret-1'}, 400),
    );
    try {
      await client.scan('v1.user.1.SIG');
      fail('expected an exception');
    } on MemberPassApiException catch (e) {
      expect(e.error, 'error');
      expect(e.toString(), isNot(contains('v1.')));
      expect(e.toString(), isNot(contains('jwt')));
    }
  });
}
