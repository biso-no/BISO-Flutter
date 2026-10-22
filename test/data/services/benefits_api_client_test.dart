import 'dart:async';
import 'dart:convert';

import 'package:biso/data/services/benefits_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> raw(String id) => {
  'id': id,
  'campusId': 'oslo',
  'section': 'member',
  'category': null,
  'title': {'nb': 'T $id', 'en': 'T $id'},
  'description': {'nb': null, 'en': null},
  'terms': {'nb': null, 'en': null},
  'imageUrl': null,
  'isFeatured': false,
  'partner': null,
  'publishEnd': null,
  'redemptionType': 'code',
  'sortOrder': 1,
  'createdAt': '2026-01-01T00:00:00.000Z',
};

http.Response json(Object body, int status) =>
    http.Response(jsonEncode(body), status);

Matcher failsWith(BenefitsApiErrorKind kind) =>
    throwsA(isA<BenefitsApiException>().having((e) => e.kind, 'kind', kind));

void main() {
  late http.Request sent;

  BenefitsApiClient clientReturning(
    http.Response response, {
    String? jwt = 'jwt-1',
  }) => BenefitsApiClient(
    httpClient: MockClient((request) async {
      sent = request;
      return response;
    }),
    jwtProvider: () async => jwt,
  );

  group('fetchBenefits', () {
    test('sends campus and token, keeps API order', () async {
      final client = clientReturning(
        json({
          'benefits': [raw('b'), raw('a')],
        }, 200),
      );
      final result = await client.fetchBenefits(campusId: 'oslo');
      expect(sent.method, 'GET');
      expect(
        sent.url.toString(),
        'https://api.biso.no/api/benefits?campus=oslo',
      );
      expect(sent.headers['Authorization'], 'Bearer jwt-1');
      expect(result.map((b) => b.id), ['b', 'a']);
    });

    test('omits campus when null', () async {
      final client = clientReturning(json({'benefits': []}, 200));
      await client.fetchBenefits();
      expect(sent.url.toString(), 'https://api.biso.no/api/benefits');
    });

    test('works without a token', () async {
      final client = clientReturning(json({'benefits': []}, 200), jwt: null);
      expect(await client.fetchBenefits(), isEmpty);
      expect(sent.headers.containsKey('Authorization'), isFalse);
    });

    test('skips malformed items without failing the list', () async {
      final client = clientReturning(
        json({
          'benefits': [
            raw('a'),
            {'id': 'broken'},
            'junk',
            raw('c'),
          ],
        }, 200),
      );
      expect((await client.fetchBenefits()).map((b) => b.id), ['a', 'c']);
    });

    test('a 404 without an error token is notDeployed', () async {
      final client = clientReturning(http.Response('Not found', 404));
      await expectLater(
        client.fetchBenefits(),
        failsWith(BenefitsApiErrorKind.notDeployed),
      );
    });

    test('503 unavailable', () async {
      final client = clientReturning(json({'error': 'unavailable'}, 503));
      await expectLater(
        client.fetchBenefits(),
        failsWith(BenefitsApiErrorKind.unavailable),
      );
    });

    test('a body without a list is unknown', () async {
      final client = clientReturning(json({'nope': 1}, 200));
      await expectLater(
        client.fetchBenefits(),
        failsWith(BenefitsApiErrorKind.unknown),
      );
    });

    test('network failure and timeout map to network', () async {
      for (final error in [http.ClientException('x'), TimeoutException('s')]) {
        final client = BenefitsApiClient(
          httpClient: MockClient((_) async => throw error),
          jwtProvider: () async => 'jwt',
        );
        await expectLater(
          client.fetchBenefits(),
          failsWith(BenefitsApiErrorKind.network),
        );
      }
    });
  });

  group('reveal', () {
    test('POSTs and returns the value', () async {
      final client = clientReturning(json({'value': 'CODE-1'}, 200));
      expect(await client.reveal('b1'), 'CODE-1');
      expect(sent.method, 'POST');
      expect(sent.url.toString(), 'https://api.biso.no/api/benefits/b1/reveal');
      expect(sent.headers['Authorization'], 'Bearer jwt-1');
    });

    test('an empty or missing value is unknown', () async {
      for (final body in [
        {'value': ''},
        {'value': 3},
        <String, dynamic>{},
      ]) {
        final client = clientReturning(json(body, 200));
        await expectLater(
          client.reveal('b1'),
          failsWith(BenefitsApiErrorKind.unknown),
        );
      }
    });

    test('maps each error token', () async {
      const cases = {
        (401, 'not_authenticated'): BenefitsApiErrorKind.notAuthenticated,
        (403, 'not_member'): BenefitsApiErrorKind.notMember,
        (404, 'not_found'): BenefitsApiErrorKind.notFound,
        (409, 'no_code'): BenefitsApiErrorKind.noCode,
        (429, 'rate_limited'): BenefitsApiErrorKind.rateLimited,
        (503, 'membership_unavailable'):
            BenefitsApiErrorKind.membershipUnavailable,
      };
      for (final entry in cases.entries) {
        final client = clientReturning(
          json({'error': entry.key.$2}, entry.key.$1),
          jwt: null,
        );
        await expectLater(client.reveal('b1'), failsWith(entry.value));
      }
    });

    test('an unrecognised token or body is unknown', () async {
      final client = clientReturning(http.Response('<html>', 502));
      await expectLater(
        client.reveal('b1'),
        failsWith(BenefitsApiErrorKind.unknown),
      );
    });

    test('the exception never carries the code', () async {
      final client = clientReturning(
        json({'error': 'no_code', 'value': 'LEAK'}, 409),
      );
      try {
        await client.reveal('b1');
        fail('should throw');
      } on BenefitsApiException catch (e) {
        expect(e.toString(), isNot(contains('LEAK')));
      }
    });

    test('retries once with a fresh token after a 401', () async {
      final tokens = <String?>[];
      var issued = 0;
      var cleared = 0;
      final client = BenefitsApiClient(
        httpClient: MockClient((request) async {
          tokens.add(request.headers['Authorization']);
          return tokens.length == 1
              ? json({'error': 'not_authenticated'}, 401)
              : json({'value': 'CODE-2'}, 200);
        }),
        jwtProvider: () async => 'jwt-${++issued}',
        invalidateJwt: () => cleared++,
      );
      expect(await client.reveal('b1'), 'CODE-2');
      expect(tokens, ['Bearer jwt-1', 'Bearer jwt-2']);
      expect(cleared, 1);
    });

    test('a second 401 is surfaced without a third request', () async {
      var requests = 0;
      var issued = 0;
      final client = BenefitsApiClient(
        httpClient: MockClient((_) async {
          requests++;
          return json({'error': 'not_authenticated'}, 401);
        }),
        jwtProvider: () async => 'jwt-${++issued}',
        invalidateJwt: () {},
      );
      await expectLater(
        client.reveal('b1'),
        failsWith(BenefitsApiErrorKind.notAuthenticated),
      );
      expect(requests, 2);
    });

    test('does not retry a request that carried no token', () async {
      var requests = 0;
      final client = BenefitsApiClient(
        httpClient: MockClient((_) async {
          requests++;
          return json({'error': 'not_authenticated'}, 401);
        }),
        jwtProvider: () async => null,
        invalidateJwt: () {},
      );
      await expectLater(
        client.reveal('b1'),
        failsWith(BenefitsApiErrorKind.notAuthenticated),
      );
      expect(requests, 1);
    });
  });
}
