import 'dart:convert';

import 'package:biso/data/services/shop_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('fetchProviders is unauthenticated: no token is fetched and no '
      'Authorization header is sent', () async {
    var jwtCalls = 0;
    late http.Request sent;
    final client = ShopApiClient(
      httpClient: MockClient((request) async {
        sent = request;
        return http.Response(jsonEncode({'providers': <Object>[]}), 200);
      }),
      jwtProvider: () async {
        jwtCalls++;
        return 'jwt-1';
      },
    );

    await client.fetchProviders();

    expect(jwtCalls, 0);
    expect(sent.headers.containsKey('Authorization'), isFalse);
  });

  test(
    'an authenticated call fetches a token and sends it as a Bearer header',
    () async {
      var jwtCalls = 0;
      late http.Request sent;
      final client = ShopApiClient(
        httpClient: MockClient((request) async {
          sent = request;
          return http.Response('', 200);
        }),
        jwtProvider: () async {
          jwtCalls++;
          return 'jwt-1';
        },
      );

      // releaseReservation() calls _send with the default authenticated: true.
      await client.releaseReservation();

      expect(jwtCalls, 1);
      expect(sent.headers['Authorization'], 'Bearer jwt-1');
    },
  );
}
