import 'dart:convert';

import 'package:biso/data/services/notifications_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object body, int status) =>
    http.Response(jsonEncode(body), status);

Matcher failsWith(NotificationsApiErrorKind kind) => throwsA(
  isA<NotificationsApiException>().having((e) => e.kind, 'kind', kind),
);

void main() {
  late List<http.Request> sent;

  setUp(() => sent = []);

  NotificationsApiClient clientReturning(
    List<http.Response> responses, {
    List<String?> jwts = const ['jwt-1'],
    void Function()? onInvalidate,
  }) {
    var call = 0;
    var token = 0;
    return NotificationsApiClient(
      httpClient: MockClient((request) async {
        sent.add(request);
        final i = call++;
        return responses[i.clamp(0, responses.length - 1)];
      }),
      jwtProvider: () async => jwts[token.clamp(0, jwts.length - 1)],
      invalidateJwt: () {
        token++;
        onInvalidate?.call();
      },
    );
  }

  test(
    'markRead posts the ids to /api/notifications/read with the token',
    () async {
      final client = clientReturning([
        json({'ok': true}, 200),
      ]);

      await client.markRead(['a', 'b']);

      final request = sent.single;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://api.biso.no/api/notifications/read',
      );
      expect(request.headers['Authorization'], 'Bearer jwt-1');
      expect(request.headers['content-type'], startsWith('application/json'));
      expect(jsonDecode(request.body), {
        'announcementIds': ['a', 'b'],
      });
    },
  );

  test('clear posts the ids to /api/notifications/clear', () async {
    final client = clientReturning([
      json({'ok': true}, 200),
    ]);

    await client.clear(['a']);

    expect(
      sent.single.url.toString(),
      'https://api.biso.no/api/notifications/clear',
    );
    expect(jsonDecode(sent.single.body), {
      'announcementIds': ['a'],
    });
  });

  test('a refused token is replaced and the request sent once more', () async {
    var invalidated = 0;
    final client = clientReturning(
      [
        json({'error': 'not_authenticated'}, 401),
        json({'ok': true}, 200),
      ],
      jwts: ['old', 'fresh'],
      onInvalidate: () => invalidated++,
    );

    await client.markRead(['a']);

    expect(invalidated, 1);
    expect(sent.map((r) => r.headers['Authorization']), [
      'Bearer old',
      'Bearer fresh',
    ]);
  });

  test('a second refusal is notAuthenticated', () async {
    final client = clientReturning(
      [
        json({'error': 'not_authenticated'}, 401),
      ],
      jwts: ['old', 'fresh'],
    );

    await expectLater(
      client.markRead(['a']),
      failsWith(NotificationsApiErrorKind.notAuthenticated),
    );
    expect(sent, hasLength(2));
  });

  test('a 404 without an error token means the routes are not deployed', () {
    final client = clientReturning([http.Response('Not Found', 404)]);
    expect(
      client.clear(['a']),
      failsWith(NotificationsApiErrorKind.notDeployed),
    );
  });

  test('error tokens map to their kinds', () async {
    final cases = {
      json({'error': 'invalid_request'}, 400):
          NotificationsApiErrorKind.invalidRequest,
      json({'error': 'rate_limited'}, 429):
          NotificationsApiErrorKind.rateLimited,
      json({'error': 'unavailable'}, 503):
          NotificationsApiErrorKind.unavailable,
    };
    for (final MapEntry(key: response, value: kind) in cases.entries) {
      await expectLater(
        clientReturning([response]).markRead(['a']),
        failsWith(kind),
      );
    }
  });

  test('a connection failure is network', () {
    final client = NotificationsApiClient(
      httpClient: MockClient((_) async => throw http.ClientException('down')),
      jwtProvider: () async => 'jwt-1',
      invalidateJwt: () {},
    );
    expect(
      client.markRead(['a']),
      failsWith(NotificationsApiErrorKind.network),
    );
  });

  test('no ids sends nothing', () async {
    final client = clientReturning([
      json({'ok': true}, 200),
    ]);

    await client.markRead([]);
    await client.clear([]);

    expect(sent, isEmpty);
  });

  test(
    'more than $kNotificationsApiBatchSize ids is refused before sending',
    () {
      final client = clientReturning([
        json({'ok': true}, 200),
      ]);
      final ids = [for (var i = 0; i <= kNotificationsApiBatchSize; i++) 'a$i'];

      expect(() => client.clear(ids), throwsArgumentError);
      expect(sent, isEmpty);
    },
  );

  test('the exception names no id and no token', () async {
    final client = clientReturning([
      json({'error': 'unavailable'}, 503),
    ]);
    try {
      await client.clear(['secret-announcement']);
      fail('expected a failure');
    } on NotificationsApiException catch (e) {
      expect(e.toString(), isNot(contains('secret-announcement')));
      expect(e.toString(), isNot(contains('jwt-1')));
    }
  });
}
