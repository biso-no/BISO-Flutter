import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:biso/data/services/device_subscription_store.dart';
import 'package:biso/data/services/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

models.Target _target({required String id, required String identifier}) =>
    models.Target(
      $id: id,
      $createdAt: '',
      $updatedAt: '',
      name: 'device',
      userId: 'user-1',
      providerId: 'push',
      providerType: 'push',
      identifier: identifier,
      expired: false,
    );

models.User _user(List<models.Target> targets) => models.User(
  $id: 'user-1',
  $createdAt: '',
  $updatedAt: '',
  name: 'Test',
  registration: '',
  status: true,
  labels: const <String>[],
  passwordUpdate: '',
  email: 'test@bi.no',
  phone: '',
  emailVerification: true,
  phoneVerification: false,
  mfa: false,
  prefs: models.Preferences(data: <String, dynamic>{}),
  targets: targets,
  accessedAt: '',
);

class _FakeAccount extends Account {
  _FakeAccount() : super(Client());

  int createCalls = 0;
  int updateCalls = 0;
  int getCalls = 0;

  /// When set, `createPushTarget` throws this instead of succeeding.
  AppwriteException? createThrows;

  /// When set, `updatePushTarget` throws this instead of succeeding.
  AppwriteException? updateThrows;

  List<models.Target> existingTargets = const <models.Target>[];

  @override
  Future<models.Target> createPushTarget({
    required String targetId,
    required String identifier,
    String? providerId,
  }) async {
    createCalls++;
    lastProviderId = providerId;
    final failure = createThrows;
    if (failure != null) throw failure;
    return _target(id: 'created-target', identifier: identifier);
  }

  String? lastProviderId;

  @override
  Future<models.Target> updatePushTarget({
    required String targetId,
    required String identifier,
  }) async {
    updateCalls++;
    final failure = updateThrows;
    if (failure != null) throw failure;
    return _target(id: targetId, identifier: identifier);
  }

  @override
  Future<models.User> get() async {
    getCalls++;
    return _user(existingTargets);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
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

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('creates a target on a first run and stores its id', () async {
    final account = _FakeAccount();
    final service = NotificationService.withAccount(account);

    expect(await service.resolvePushTarget('token-1'), 'created-target');
    expect(account.createCalls, 1);
    expect(await DeviceSubscriptionStore().readTargetId(), 'created-target');
  });

  test(
    'registers against the FCM provider id "push" - the project has no '
    'provider called "fcm", which is why targets never got created',
    () async {
      final account = _FakeAccount();
      await NotificationService.withAccount(account).resolvePushTarget('t');
      expect(account.lastProviderId, 'push');
    },
  );

  test('updates the stored target on a later run instead of recreating', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'push_target_id': 'stored-target',
    });
    final account = _FakeAccount();

    final resolved = await NotificationService.withAccount(
      account,
    ).resolvePushTarget('token-2');

    expect(resolved, 'stored-target');
    expect(account.updateCalls, 1);
    expect(account.createCalls, 0);
  });

  test('falls back to creating when the stored target is gone', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'push_target_id': 'deleted-target',
    });
    final account = _FakeAccount()
      ..updateThrows = AppwriteException('not found', 404);

    expect(
      await NotificationService.withAccount(account).resolvePushTarget('t'),
      'created-target',
    );
    expect(account.createCalls, 1);
  });

  test(
    'adopts the existing target when creation 409s - this is the case that '
    'silently broke every subscription after the first launch',
    () async {
      final account = _FakeAccount()
        ..createThrows = AppwriteException('target exists', 409)
        ..existingTargets = [
          _target(id: 'other-device', identifier: 'someone-elses-token'),
          _target(id: 'this-device', identifier: 'token-1'),
        ];

      final resolved = await NotificationService.withAccount(
        account,
      ).resolvePushTarget('token-1');

      expect(resolved, 'this-device');
      expect(account.getCalls, 1);
      expect(await DeviceSubscriptionStore().readTargetId(), 'this-device');
    },
  );

  test('returns null when a 409 has no matching target to adopt', () async {
    final account = _FakeAccount()
      ..createThrows = AppwriteException('target exists', 409)
      ..existingTargets = const <models.Target>[];

    expect(
      await NotificationService.withAccount(account).resolvePushTarget('token-1'),
      isNull,
    );
  });

  test(
    'forgets stale subscriber ids when the target changes identity, so the '
    'next reconcile re-subscribes rather than computing an empty diff against '
    'subscribers that belong to a target which no longer exists',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'push_target_id': 'old-target',
        'topic_subscriber_ids': '{"news_oslo":"sub-1"}',
      });
      final account = _FakeAccount()
        ..updateThrows = AppwriteException('not found', 404);

      final resolved = await NotificationService.withAccount(
        account,
      ).resolvePushTarget('token-1');

      expect(resolved, 'created-target');
      expect(await DeviceSubscriptionStore().readSubscriberIds(), isEmpty);
    },
  );

  test(
    'keeps subscriber ids when the target id is unchanged, so a routine token '
    'refresh does not churn every subscription',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'push_target_id': 'stored-target',
        'topic_subscriber_ids': '{"news_oslo":"sub-1"}',
      });
      final account = _FakeAccount();

      await NotificationService.withAccount(account).resolvePushTarget('t2');

      expect(
        await DeviceSubscriptionStore().readSubscriberIds(),
        {'news_oslo': 'sub-1'},
      );
    },
  );

  test('returns null on a non-409 create failure without calling get', () async {
    final account = _FakeAccount()
      ..createThrows = AppwriteException('offline', 500);

    expect(
      await NotificationService.withAccount(account).resolvePushTarget('t'),
      isNull,
    );
    expect(account.getCalls, 0);
  });
}
