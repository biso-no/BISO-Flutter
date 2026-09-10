import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:biso/data/services/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAccount extends Account {
  _FakeAccount(this._prefs) : super(Client());

  Map<String, dynamic> _prefs;
  Map<String, dynamic> get saved => _prefs;

  /// How many times [updatePrefs] was called — used to assert that a read
  /// path does *not* write, without depending on the exact shape written.
  int updatePrefsCalls = 0;

  /// When true, [getPrefs] throws instead of returning [_prefs] - simulates a
  /// network/read failure distinct from "nothing stored yet", which is
  /// instead expressed by an empty (or absent-key) [_prefs].
  bool shouldFail = false;

  @override
  Future<models.Preferences> getPrefs() async {
    if (shouldFail) {
      throw AppwriteException('offline');
    }
    return models.Preferences(data: Map<String, dynamic>.from(_prefs));
  }

  @override
  Future<models.User> updatePrefs({required Map prefs}) async {
    updatePrefsCalls++;
    _prefs = Map<String, dynamic>.from(prefs);
    throw UnimplementedError('return value unused by the code under test');
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

  group('loadTopicIntent', () {
    test('returns the defaults for an account that has never chosen', () async {
      final service = NotificationService.withAccount(
        _FakeAccount(<String, dynamic>{}),
      );
      expect(await service.loadTopicIntent(), {
        'news': true,
        'events': true,
        'jobs': true,
        'shop': true,
      });
    });

    test('reads a stored intent map', () async {
      final service = NotificationService.withAccount(
        _FakeAccount(<String, dynamic>{
          'notification_topics': <String, dynamic>{
            'news': false,
            'events': true,
            'jobs': false,
            'shop': false,
          },
        }),
      );
      expect((await service.loadTopicIntent())['news'], isFalse);
    });

    test(
      'migrates a legacy topic_subscriptions map, renaming products to shop '
      'and dropping expenses',
      () async {
        final service = NotificationService.withAccount(
          _FakeAccount(<String, dynamic>{
            'topic_subscriptions': <String, dynamic>{
              'products': false,
              'expenses': true,
              'events': false,
            },
          }),
        );
        final intent = await service.loadTopicIntent();
        expect(intent['shop'], isFalse);
        expect(intent['events'], isFalse);
        expect(intent.containsKey('expenses'), isFalse);
      },
    );

    test(
      'rethrows when the preferences read itself fails, instead of reporting '
      'it the same way as "nothing saved yet" - a caller must be able to '
      'tell the two apart, or a later toggle persists fabricated defaults '
      'over the student\'s real saved intent',
      () async {
        final account = _FakeAccount(<String, dynamic>{})..shouldFail = true;
        final service = NotificationService.withAccount(account);

        expect(
          () => service.loadTopicIntent(),
          throwsA(isA<AppwriteException>()),
        );
      },
    );
  });

  group('hasAnsweredTopicPrompt', () {
    test('is false for a brand new account', () async {
      final service = NotificationService.withAccount(
        _FakeAccount(<String, dynamic>{}),
      );
      expect(await service.hasAnsweredTopicPrompt(), isFalse);
    });

    test('is true once the marker is stored', () async {
      final service = NotificationService.withAccount(
        _FakeAccount(<String, dynamic>{
          'notification_topics_set_at': '2026-09-09T10:00:00.000Z',
        }),
      );
      expect(await service.hasAnsweredTopicPrompt(), isTrue);
    });

    test(
      'is false for a legacy account with only an old topic_subscriptions map '
      '- that map used to be written automatically on every launch, never '
      'because a student chose anything, so its presence cannot be told apart '
      'from someone who was never asked',
      () async {
        final service = NotificationService.withAccount(
          _FakeAccount(<String, dynamic>{
            'topic_subscriptions': <String, dynamic>{'events': false},
          }),
        );
        expect(await service.hasAnsweredTopicPrompt(), isFalse);
      },
    );

    test(
      'is false even when both the legacy map and subscriber ids are present '
      'but notification_topics_set_at is not, matching a real pre-migration '
      'account that has never seen the new prompt',
      () async {
        final service = NotificationService.withAccount(
          _FakeAccount(<String, dynamic>{
            'topic_subscriptions': <String, dynamic>{'events': false},
            'topic_subscriber_ids': <String, dynamic>{'events': 'sub-1'},
          }),
        );
        expect(await service.hasAnsweredTopicPrompt(), isFalse);
      },
    );
  });

  group('_loadTopicSubscriptions (via ensureTopicSubscriptionsLoaded)', () {
    test(
      'does not write prefs when topic_subscriptions is absent, so the '
      'legacy key stays read-only and cannot be mistaken for a real answer '
      'to the first-run prompt',
      () async {
        final account = _FakeAccount(<String, dynamic>{});
        final service = NotificationService.withAccount(account);

        final loaded = await service.ensureTopicSubscriptionsLoaded();

        expect(account.updatePrefsCalls, 0);
        expect(loaded, {
          'events': true,
          'products': true,
          'jobs': true,
          'expenses': false,
        });
      },
    );

    test(
      'still does not write prefs when a stored topic_subscriptions map is '
      'present, either - loading must never have a side effect on prefs',
      () async {
        final account = _FakeAccount(<String, dynamic>{
          'topic_subscriptions': <String, dynamic>{'events': false},
        });
        final service = NotificationService.withAccount(account);

        await service.ensureTopicSubscriptionsLoaded();

        expect(account.updatePrefsCalls, 0);
      },
    );
  });
}
