import 'dart:convert';

import 'package:biso/data/models/membership_overview.dart';
import 'package:biso/data/models/payment_provider.dart';
import 'package:biso/data/services/membership_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late http.Request sent;

  MembershipApiClient clientReturning(http.Response response) {
    return MembershipApiClient(
      httpClient: MockClient((request) async {
        sent = request;
        return response;
      }),
      jwtProvider: () async => 'jwt-1',
    );
  }

  final overviewBody = jsonEncode({
    'state': 'needs_bi_link',
    'studentId': null,
    'isMember': false,
    'memberships': <Object>[],
    'expiredMemberships': <Object>[],
    'currentExpiry': null,
    'reason': 'no_student_id',
    'checkedAt': '2026-09-15T08:00:00.000Z',
    'offeredPlans': <Object>[],
    'defaultCampusId': null,
    'campuses': [
      {'id': '1', 'name': 'Oslo'},
    ],
  });

  test('fetches the overview with the student token', () async {
    final client = clientReturning(http.Response(overviewBody, 200));

    final overview = await client.fetchOverview();

    expect(sent.method, 'GET');
    expect(sent.url.toString(), 'https://api.biso.no/api/membership');
    expect(sent.headers['Authorization'], 'Bearer jwt-1');
    expect(overview.state, MembershipGateState.needsBiLink);
  });

  test('asks the server to re-check when refreshing', () async {
    final client = clientReturning(http.Response(overviewBody, 200));

    await client.fetchOverview(refresh: true);

    expect(sent.url.toString(), 'https://api.biso.no/api/membership?refresh=1');
  });

  test('reports a missing session as unauthorized', () async {
    final client = clientReturning(
      http.Response(jsonEncode({'message': 'Authentication required'}), 401),
    );

    await expectLater(
      client.fetchOverview(),
      throwsA(
        isA<MembershipApiException>().having(
          (e) => e.isUnauthorized,
          'isUnauthorized',
          isTrue,
        ),
      ),
    );
  });

  test('starts a membership checkout that returns to the app', () async {
    final client = clientReturning(
      http.Response(
        jsonEncode({
          'checkoutUrl': 'https://vipps.example/checkout',
          'orderId': 'order-1',
        }),
        200,
      ),
    );

    final started = await client.startCheckout(
      provider: PaymentProvider.vipps,
      planId: '71',
      campusId: '2',
    );

    expect(sent.method, 'POST');
    expect(
      sent.url.toString(),
      'https://api.biso.no/api/payment/vipps/membership-checkout',
    );
    expect(jsonDecode(sent.body), {
      'campusId': '2',
      'client': 'app',
      'planId': '71',
    });
    expect(started.checkoutUrl, 'https://vipps.example/checkout');
    expect(started.orderId, 'order-1');
  });

  test("surfaces the server's reason when a purchase is refused", () async {
    final client = clientReturning(
      http.Response(
        jsonEncode({'message': 'Your membership already covers this period.'}),
        409,
      ),
    );

    await expectLater(
      client.startCheckout(
        provider: PaymentProvider.stripe,
        planId: '71',
        campusId: '1',
      ),
      throwsA(
        isA<MembershipApiException>()
            .having((e) => e.isAlreadyCovered, 'isAlreadyCovered', isTrue)
            .having(
              (e) => e.message,
              'message',
              'Your membership already covers this period.',
            ),
      ),
    );
  });

  test('refuses a checkout answer without a payment link', () async {
    final client = clientReturning(
      http.Response(jsonEncode({'orderId': 'order-1'}), 200),
    );

    await expectLater(
      client.startCheckout(
        provider: PaymentProvider.vipps,
        planId: '71',
        campusId: '1',
      ),
      throwsA(isA<MembershipApiException>()),
    );
  });
}
