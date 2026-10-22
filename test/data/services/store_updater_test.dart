import 'package:biso/data/services/app_store_channel.dart';
import 'package:biso/data/services/store_updater.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePlay implements PlayUpdates {
  FakePlay({
    required this.available,
    this.throwOnCheck = false,
    this.throwOnPerform = false,
  });

  final bool available;
  final bool throwOnCheck;
  final bool throwOnPerform;
  bool checked = false;
  bool performed = false;

  @override
  Future<bool> immediateUpdateAvailable() async {
    checked = true;
    if (throwOnCheck) {
      throw PlatformException(code: 'ERROR_API_NOT_AVAILABLE');
    }
    return available;
  }

  @override
  Future<void> performImmediateUpdate() async {
    if (throwOnPerform) {
      throw PlatformException(code: 'ERROR_UPDATE_FAILED');
    }
    performed = true;
  }
}

final _market = Uri.parse('market://details?id=com.biso.no');
final _playWeb = Uri.parse(
  'https://play.google.com/store/apps/details?id=com.biso.no',
);
final _appStoreWeb = Uri.parse('https://apps.apple.com/app/id6468173379');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Uri> opened;

  /// Records every URL and answers with [result], or throws for any scheme
  /// in [throwFor].
  UrlOpener opener({
    bool Function(Uri uri)? result,
    Set<String> throwFor = const {},
  }) {
    return (uri) async {
      opened.add(uri);
      if (throwFor.contains(uri.scheme)) {
        throw PlatformException(code: 'ACTIVITY_NOT_FOUND');
      }
      return result?.call(uri) ?? true;
    };
  }

  setUp(() => opened = []);

  group('Android', () {
    test('runs Play immediate update when one is available', () async {
      final play = FakePlay(available: true);

      await StoreUpdater(
        platform: TargetPlatform.android,
        play: play,
        openUrl: opener(),
      ).startUpdate();

      expect(play.performed, isTrue);
      expect(opened, isEmpty);
    });

    test(
      'falls back to the Play Store listing when Play has no update',
      () async {
        final play = FakePlay(available: false);

        await StoreUpdater(
          platform: TargetPlatform.android,
          play: play,
          openUrl: opener(),
        ).startUpdate();

        expect(play.performed, isFalse);
        expect(opened, [_market]);
      },
    );

    test('falls back to the https listing when market: cannot open', () async {
      await StoreUpdater(
        platform: TargetPlatform.android,
        play: FakePlay(available: false),
        openUrl: opener(result: (uri) => uri.scheme != 'market'),
      ).startUpdate();

      expect(opened, [_market, _playWeb]);
    });

    test('falls back to the https listing when market: throws', () async {
      await StoreUpdater(
        platform: TargetPlatform.android,
        play: FakePlay(available: false),
        openUrl: opener(throwFor: {'market'}),
      ).startUpdate();

      expect(opened, [_market, _playWeb]);
    });

    test('falls back when Play throws on perform', () async {
      final play = FakePlay(available: true, throwOnPerform: true);

      await StoreUpdater(
        platform: TargetPlatform.android,
        play: play,
        openUrl: opener(),
      ).startUpdate();

      expect(opened.first.scheme, 'market');
      expect(opened, [_market]);
    });

    test('falls back when Play throws on the availability check', () async {
      final play = FakePlay(available: true, throwOnCheck: true);

      await StoreUpdater(
        platform: TargetPlatform.android,
        play: play,
        openUrl: opener(),
      ).startUpdate();

      expect(play.performed, isFalse);
      expect(opened, [_market]);
    });

    test('never throws when no store link opens either', () async {
      await StoreUpdater(
        platform: TargetPlatform.android,
        play: FakePlay(available: false),
        openUrl: opener(throwFor: {'market', 'https'}),
      ).startUpdate();

      expect(opened, [_market, _playWeb]);
    });
  });

  group('iOS', () {
    const channel = MethodChannel('test/app_store');
    late List<MethodCall> calls;

    void handle(Future<Object?>? Function(MethodCall call)? handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            handler == null
                ? null
                : (call) {
                    calls.add(call);
                    return handler(call);
                  },
          );
    }

    setUp(() => calls = []);
    tearDown(() => handle(null));

    StoreUpdater updater({UrlOpener? openUrl}) => StoreUpdater(
      platform: TargetPlatform.iOS,
      appStore: const AppStoreChannel(channel),
      openUrl: openUrl ?? opener(),
    );

    test('opens the App Store sheet for item 6468173379', () async {
      handle((call) async => null);

      await updater().startUpdate();

      expect(calls.single.method, 'showProductPage');
      expect(calls.single.arguments, {'itemId': '6468173379'});
      expect(opened, isEmpty);
    });

    test(
      'falls back to the App Store URL when the sheet fails to load',
      () async {
        handle((call) async => throw PlatformException(code: 'load_failed'));

        await updater().startUpdate();

        expect(calls, hasLength(1));
        expect(opened.single, _appStoreWeb);
      },
    );

    test(
      'falls back to the App Store URL when there is no presenter',
      () async {
        handle((call) async => throw PlatformException(code: 'no_presenter'));

        await updater().startUpdate();

        expect(opened.single, _appStoreWeb);
      },
    );

    test(
      'falls back to the App Store URL without the native channel',
      () async {
        // No handler: the call ends in a MissingPluginException.
        await updater().startUpdate();

        expect(opened.single, _appStoreWeb);
      },
    );

    test('never throws when the App Store URL cannot open', () async {
      handle((call) async => throw PlatformException(code: 'load_failed'));

      await updater(openUrl: opener(throwFor: {'https'})).startUpdate();

      expect(opened.single, _appStoreWeb);
    });
  });

  group('InAppUpdatePlayUpdates', () {
    // The channel `in_app_update` 5.0.0 talks to its Kotlin plugin over.
    const channel = MethodChannel('de.ffuf.in_app_update/methods');

    void handle(Future<Object?>? Function(MethodCall call)? handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handler);
    }

    tearDown(() => handle(null));

    Map<String, Object?> info({
      required int availability,
      required bool immediateAllowed,
    }) => {
      'updateAvailability': availability,
      'immediateAllowed': immediateAllowed,
      'immediateAllowedPreconditions': null,
      'flexibleAllowed': true,
      'flexibleAllowedPreconditions': null,
      'availableVersionCode': 94,
      'installStatus': 0,
      'packageName': 'com.biso.no',
      'clientVersionStalenessDays': null,
      'updatePriority': 0,
    };

    const updateAvailable = 2;
    const updateNotAvailable = 1;

    test('reports an update Play can install immediately', () async {
      handle(
        (call) async =>
            info(availability: updateAvailable, immediateAllowed: true),
      );

      expect(
        await const InAppUpdatePlayUpdates().immediateUpdateAvailable(),
        isTrue,
      );
    });

    test('does not report an update Play only allows flexibly', () async {
      handle(
        (call) async =>
            info(availability: updateAvailable, immediateAllowed: false),
      );

      expect(
        await const InAppUpdatePlayUpdates().immediateUpdateAvailable(),
        isFalse,
      );
    });

    test('does not report an update when Play has none', () async {
      handle(
        (call) async =>
            info(availability: updateNotAvailable, immediateAllowed: true),
      );

      expect(
        await const InAppUpdatePlayUpdates().immediateUpdateAvailable(),
        isFalse,
      );
    });

    test('completes when the student declines the update', () async {
      handle(
        (call) async => throw PlatformException(code: 'USER_DENIED_UPDATE'),
      );

      await const InAppUpdatePlayUpdates().performImmediateUpdate();
    });

    test('throws when Play fails to run the update', () async {
      handle(
        (call) async => throw PlatformException(code: 'IN_APP_UPDATE_FAILED'),
      );

      await expectLater(
        const InAppUpdatePlayUpdates().performImmediateUpdate(),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  test('does nothing on platforms without a store prompt', () async {
    final play = FakePlay(available: true);

    await StoreUpdater(
      platform: TargetPlatform.macOS,
      play: play,
      openUrl: opener(),
    ).startUpdate();

    expect(play.checked, isFalse);
    expect(opened, isEmpty);
  });
}
