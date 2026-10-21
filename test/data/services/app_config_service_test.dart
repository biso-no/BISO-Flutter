import 'dart:convert';

import 'package:biso/data/models/app_config.dart';
import 'package:biso/data/models/update_policy.dart';
import 'package:biso/data/services/app_config_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  AppConfigService serviceReturning(http.Response response) =>
      AppConfigService(httpClient: MockClient((_) async => response));

  AppConfigService offlineService() => AppConfigService(
    httpClient: MockClient((_) async => throw const SocketishFailure()),
  );

  test('reads the switches the server actually sent', () async {
    final config = await serviceReturning(
      http.Response(
        jsonEncode({
          'features': {
            'departures': true,
            'expenses': false,
            'marketplace': true,
          },
        }),
        200,
      ),
    ).getConfig();

    expect(config.expensesEnabled, isFalse);
    expect(config.marketplaceEnabled, isTrue);
  });

  test('reads the version policy for each platform from the network', () async {
    final config = await serviceReturning(
      http.Response(
        jsonEncode({
          'features': {
            'departures': true,
            'expenses': false,
            'marketplace': true,
          },
          'versions': {
            'ios': {'minimum': '2.4.0', 'recommended': null},
            'android': {'minimum': '2.4.0', 'recommended': '2.4.1'},
          },
        }),
        200,
      ),
    ).getConfig();

    expect(config.source, AppConfigSource.network);
    expect(config.iosUpdates, const UpdatePolicy(minimum: '2.4.0'));
    expect(
      config.androidUpdates,
      const UpdatePolicy(minimum: '2.4.0', recommended: '2.4.1'),
    );
  });

  test(
    'a cached config says it came from the cache and carries no policy',
    () async {
      await serviceReturning(
        http.Response(
          jsonEncode({
            'features': {
              'departures': true,
              'expenses': true,
              'marketplace': true,
            },
            'versions': {
              'ios': {'minimum': '9.9.9'},
            },
          }),
          200,
        ),
      ).getConfig();

      final config = await offlineService().getConfig();

      expect(config.source, AppConfigSource.cache);
      expect(config.iosUpdates, UpdatePolicy.none);
    },
  );

  test('a malformed versions object means no policy', () async {
    final config = await serviceReturning(
      http.Response(
        jsonEncode({
          'features': {},
          'versions': {
            'ios': 'soon',
            'android': {'minimum': 240},
          },
        }),
        200,
      ),
    ).getConfig();

    expect(config.iosUpdates, UpdatePolicy.none);
    expect(config.androidUpdates.minimum, isNull);
  });

  test(
    'refuses to invent a config when the fetch fails and nothing is cached',
    () async {
      // Returning a default here is what made an offline launch announce that
      // BISO had switched reimbursements off — a claim about BISO's settings
      // that a failed fetch is no evidence for. Failing loudly makes
      // `expensesAvailabilityProvider` read `unknown`: "we do not know".
      await expectLater(
        offlineService().getConfig(),
        throwsA(isA<AppConfigUnavailableException>()),
      );
    },
  );

  test('falls back to a fresh cache when the fetch fails', () async {
    await serviceReturning(
      http.Response(
        jsonEncode({
          'features': {
            'departures': true,
            'expenses': true,
            'marketplace': true,
          },
        }),
        200,
      ),
    ).getConfig();

    final config = await offlineService().getConfig();

    expect(config.expensesEnabled, isTrue);
  });

  test(
    'refuses to invent a config when the server answers with an error',
    () async {
      await expectLater(
        serviceReturning(http.Response('nope', 500)).getConfig(),
        throwsA(isA<AppConfigUnavailableException>()),
      );
    },
  );
}

/// Stands in for the kind of failure an offline launch produces.
class SocketishFailure implements Exception {
  const SocketishFailure();
}
