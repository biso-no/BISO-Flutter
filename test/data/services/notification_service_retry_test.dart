import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:biso/data/services/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// An [Account] whose `getPrefs` can be made to fail on demand, so the load
/// path can be exercised without a network or a signed-in user.
class _FakeAccount extends Account {
  _FakeAccount() : super(Client());

  int getPrefsCalls = 0;
  bool shouldFail = false;

  @override
  Future<models.Preferences> getPrefs() async {
    getPrefsCalls++;
    if (shouldFail) {
      throw AppwriteException('offline');
    }
    return models.Preferences(
      data: <String, dynamic>{
        'topic_subscriptions': <String, dynamic>{'events': false},
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Constructing an Appwrite Client asks path_provider for a cookie
    // directory, which has no implementation under `flutter test`.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  group('ensureTopicSubscriptionsLoaded', () {
    test(
      'retries after a failed read instead of latching "loaded" for the rest '
      'of the session',
      () async {
        final account = _FakeAccount();
        final service = NotificationService.withAccount(account);

        account.shouldFail = true;
        await service.ensureTopicSubscriptionsLoaded();
        expect(account.getPrefsCalls, 1);

        account.shouldFail = false;
        final loaded = await service.ensureTopicSubscriptionsLoaded();

        expect(
          account.getPrefsCalls,
          2,
          reason: 'the failed first read should not count as loaded',
        );
        expect(loaded['events'], isFalse);
      },
    );

    test('does not re-read prefs once they have loaded successfully', () async {
      final account = _FakeAccount();
      final service = NotificationService.withAccount(account);

      await service.ensureTopicSubscriptionsLoaded();
      await service.ensureTopicSubscriptionsLoaded();

      expect(account.getPrefsCalls, 1);
    });
  });
}
