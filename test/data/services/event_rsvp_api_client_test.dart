import 'dart:convert';

import 'package:biso/data/models/event_rsvp.dart';
import 'package:biso/data/services/event_rsvp_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object body, int status) =>
    http.Response(jsonEncode(body), status);

Matcher failsWith(EventRsvpApiErrorKind kind) =>
    throwsA(isA<EventRsvpApiException>().having((e) => e.kind, 'kind', kind));

final okBody = {
  'counts': {'going': 2, 'maybe': 1},
  'mine': 'going',
  'open': true,
};

void main() {
  late List<http.Request> sent;

  setUp(() => sent = []);

  EventRsvpApiClient clientReturning(
    List<http.Response> responses, {
    List<String?> jwts = const ['jwt-1'],
  }) {
    var call = 0;
    var token = 0;
    return EventRsvpApiClient(
      httpClient: MockClient((request) async {
        sent.add(request);
        final i = call++;
        return responses[i.clamp(0, responses.length - 1)];
      }),
      jwtProvider: () async => jwts[token.clamp(0, jwts.length - 1)],
      invalidateJwt: () => token++,
    );
  }

  test('fetch signed out sends no Authorization header', () async {
    final client = clientReturning([json(okBody, 200)]);
    final summary = await client.fetch('e1', signedIn: false);
    expect(sent.single.method, 'GET');
    expect(
      sent.single.url.toString(),
      'https://api.biso.no/api/events/e1/rsvp',
    );
    expect(sent.single.headers.containsKey('Authorization'), isFalse);
    expect(summary.going, 2);
  });

  test('fetch signed in sends the bearer token', () async {
    final client = clientReturning([json(okBody, 200)]);
    await client.fetch('e1', signedIn: true);
    expect(sent.single.headers['Authorization'], 'Bearer jwt-1');
  });

  test('respond posts the wire status', () async {
    final client = clientReturning([json(okBody, 200)]);
    await client.respond('e1', EventRsvpStatus.notGoing);
    expect(sent.last.method, 'POST');
    expect(sent.last.headers['content-type'], startsWith('application/json'));
    expect(jsonDecode(sent.last.body), {'status': 'not_going'});
    await client.respond('e1', null);
    expect(jsonDecode(sent.last.body), {'status': null});
  });

  test('retries once with a fresh token after a 401', () async {
    final client = clientReturning(
      [
        json({'error': 'not_authenticated'}, 401),
        json(okBody, 200),
      ],
      jwts: ['old', 'fresh'],
    );
    await client.respond('e1', EventRsvpStatus.going);
    expect(sent, hasLength(2));
    expect(sent[0].headers['Authorization'], 'Bearer old');
    expect(sent[1].headers['Authorization'], 'Bearer fresh');
  });

  test('maps 409, 403 and 429 to their kinds', () async {
    await expectLater(
      clientReturning([
        json({'error': 'closed'}, 409),
      ]).respond('e1', EventRsvpStatus.going),
      failsWith(EventRsvpApiErrorKind.closed),
    );
    await expectLater(
      clientReturning([
        json({'error': 'members_only'}, 403),
      ]).respond('e1', EventRsvpStatus.going),
      failsWith(EventRsvpApiErrorKind.membersOnly),
    );
    await expectLater(
      clientReturning([
        json({'error': 'rate_limited'}, 429),
      ]).respond('e1', EventRsvpStatus.going),
      failsWith(EventRsvpApiErrorKind.rateLimited),
    );
  });

  test('404 without a token is notDeployed', () async {
    await expectLater(
      clientReturning([
        http.Response('Not found', 404),
      ]).fetch('e1', signedIn: false),
      failsWith(EventRsvpApiErrorKind.notDeployed),
    );
  });

  test('404 with not_found is notFound', () async {
    await expectLater(
      clientReturning([
        json({'error': 'not_found'}, 404),
      ]).fetch('e1', signedIn: false),
      failsWith(EventRsvpApiErrorKind.notFound),
    );
  });

  test('an unparseable 2xx body is unknown 502', () async {
    await expectLater(
      clientReturning([
        json({'nope': 1}, 200),
      ]).fetch('e1', signedIn: false),
      throwsA(
        isA<EventRsvpApiException>()
            .having((e) => e.kind, 'kind', EventRsvpApiErrorKind.unknown)
            .having((e) => e.statusCode, 'status', 502),
      ),
    );
  });

  test('a second 401 is surfaced without a third request', () async {
    final client = clientReturning(
      [
        json({'error': 'not_authenticated'}, 401),
      ],
      jwts: ['old', 'fresh'],
    );
    await expectLater(
      client.respond('e1', EventRsvpStatus.going),
      failsWith(EventRsvpApiErrorKind.notAuthenticated),
    );
    expect(sent, hasLength(2));
  });

  test('does not retry a request that carried no token', () async {
    final client = clientReturning([
      json({'error': 'not_authenticated'}, 401),
    ]);
    await expectLater(
      client.fetch('e1', signedIn: false),
      failsWith(EventRsvpApiErrorKind.notAuthenticated),
    );
    expect(sent, hasLength(1));
  });
}
