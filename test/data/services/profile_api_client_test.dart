import 'dart:convert';

import 'package:biso/data/services/profile_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late http.Request sent;

  ProfileApiClient clientReturning(
    http.Response response, {
    String? jwt = 'jwt-1',
  }) {
    return ProfileApiClient(
      httpClient: MockClient((request) async {
        sent = request;
        return response;
      }),
      jwtProvider: () async => jwt,
    );
  }

  test('saves fields with a bearer token and returns the saved row', () async {
    final client = clientReturning(
      http.Response(
        jsonEncode({
          'success': true,
          'profile': {r'$id': 'user-1', 'name': 'Ada', 'is_public': true},
        }),
        200,
      ),
    );

    final profile = await client.upsert({'name': 'Ada', 'is_public': true});

    expect(sent.method, 'PUT');
    expect(sent.url.toString(), 'https://api.biso.no/api/profile');
    expect(sent.headers['Authorization'], 'Bearer jwt-1');
    expect(jsonDecode(sent.body), {'name': 'Ada', 'is_public': true});
    expect(profile[r'$id'], 'user-1');
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
      client.upsert({'name': 'Ada'}),
      throwsA(
        isA<ProfileApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', 'Authentication required'),
      ),
    );
    expect(sent.headers.containsKey('Authorization'), isFalse);
  });

  test('surfaces the server message when a value is rejected', () async {
    final client = clientReturning(
      http.Response(
        jsonEncode({'success': false, 'error': 'Invalid profile'}),
        400,
      ),
    );

    await expectLater(
      client.upsert({'name': 'x' * 31}),
      throwsA(
        isA<ProfileApiException>().having(
          (e) => e.message,
          'message',
          'Invalid profile',
        ),
      ),
    );
  });

  test('turns a non-JSON gateway error into a readable failure', () async {
    final client = clientReturning(http.Response('<html>502</html>', 502));

    await expectLater(
      client.upsert({'name': 'Ada'}),
      throwsA(
        isA<ProfileApiException>()
            .having((e) => e.statusCode, 'statusCode', 502)
            .having(
              (e) => e.message,
              'message',
              'We could not save your profile.',
            ),
      ),
    );
  });
}
