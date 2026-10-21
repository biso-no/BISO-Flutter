import 'dart:async';

import 'package:biso/data/models/app_config.dart';
import 'package:biso/data/models/update_decision.dart';
import 'package:biso/data/models/update_policy.dart';
import 'package:biso/data/services/app_config_service.dart';
import 'package:biso/data/services/update_snooze_store.dart';
import 'package:biso/providers/config/app_config_provider.dart';
import 'package:biso/providers/config/update_prompt_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers `getConfig` from a queue: each call takes the next answer, and the
/// last one keeps answering every call after it.
///
/// An answer is an [AppConfig], a [Completer] whose config is still on its
/// way, or an [Exception] to throw.
class _FakeConfigService implements AppConfigService {
  _FakeConfigService(List<Object> answers) : _answers = [...answers];

  final List<Object> _answers;
  int calls = 0;

  @override
  Future<AppConfig> getConfig() async {
    calls++;
    final answer = _answers.length > 1 ? _answers.removeAt(0) : _answers.single;
    return switch (answer) {
      final AppConfig config => config,
      final Completer<AppConfig> pending => pending.future,
      final Exception error => throw error,
      _ => throw ArgumentError.value(answer, 'answer'),
    };
  }
}

/// A snooze store whose read has not come back yet.
class _SlowSnoozeStore implements UpdateSnoozeStore {
  final reading = Completer<UpdateSnooze?>();

  @override
  Future<UpdateSnooze?> read() => reading.future;

  @override
  Future<void> write(UpdateSnooze snooze) async {}
}

AppConfig _network({
  UpdatePolicy android = UpdatePolicy.none,
  UpdatePolicy ios = UpdatePolicy.none,
}) => AppConfig(androidUpdates: android, iosUpdates: ios);

AppConfig _cached({UpdatePolicy android = UpdatePolicy.none}) =>
    AppConfig(source: AppConfigSource.cache, androidUpdates: android);

const _blocking = UpdatePolicy(minimum: '2.4.0');
const _nudging = UpdatePolicy(recommended: '2.4.1');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;

  setUp(() {
    now = DateTime(2026, 10, 22, 12);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  ProviderContainer start(
    _FakeConfigService service, {
    String installed = '2.3.2',
    TargetPlatform? platform = TargetPlatform.android,
    Future<String> Function()? installedVersion,
    UpdateSnoozeStore? snoozeStore,
  }) {
    final container = ProviderContainer(
      overrides: [
        appConfigServiceProvider.overrideWithValue(service),
        installedVersionProvider.overrideWith(
          (_) => installedVersion?.call() ?? Future.value(installed),
        ),
        updatePlatformProvider.overrideWithValue(platform),
        updateClockProvider.overrideWithValue(() => now),
        if (snoozeStore != null)
          updateSnoozeStoreProvider.overrideWithValue(snoozeStore),
      ],
    );
    addTearDown(container.dispose);
    container.listen(updatePromptProvider, (_, _) {});
    return container;
  }

  /// Lets the config fetch, the installed version and the stored snooze all
  /// arrive, then returns the prompt they add up to.
  ///
  /// Pumps the event queue until `appConfigProvider` has an answer (or has
  /// failed to get one), and once more for the decision that follows it.
  Future<UpdatePrompt> settle(ProviderContainer container) async {
    container.read(updatePromptProvider);
    for (var i = 0; i < 20; i++) {
      await pumpEventQueue();
      if (!container.read(appConfigProvider).isLoading) break;
    }
    await pumpEventQueue();
    return container.read(updatePromptProvider);
  }

  /// Asks for the config again, as a resume or a pull-to-refresh would.
  Future<UpdatePrompt> reread(ProviderContainer container) {
    container.invalidate(appConfigProvider);
    return settle(container);
  }

  group('updatePromptProvider', () {
    test('a fresh minimum above the installed version blocks', () async {
      final container = start(
        _FakeConfigService([_network(android: _blocking)]),
      );
      expect(await settle(container), UpdatePrompt.required);
    });

    test('a fresh recommendation above the installed version nudges', () async {
      final container = start(
        _FakeConfigService([_network(android: _nudging)]),
        installed: '2.4.0',
      );
      expect(await settle(container), UpdatePrompt.recommended);
    });

    test('says nothing before any answer has arrived', () async {
      final pending = Completer<AppConfig>();
      final container = start(_FakeConfigService([pending]));

      await pumpEventQueue();
      expect(container.read(appConfigProvider).isLoading, isTrue);
      expect(container.read(updatePromptProvider), UpdatePrompt.none);

      pending.complete(_network(android: _blocking));
      expect(await settle(container), UpdatePrompt.required);
    });

    test('reads the policy of its own platform only', () async {
      final config = _network(ios: _blocking, android: _nudging);

      final onIos = start(
        _FakeConfigService([config]),
        platform: TargetPlatform.iOS,
      );
      expect(await settle(onIos), UpdatePrompt.required);

      final onAndroid = start(_FakeConfigService([config]));
      expect(await settle(onAndroid), UpdatePrompt.recommended);
    });

    test('a cached re-read does not lift a block', () async {
      final service = _FakeConfigService([
        _network(android: _blocking),
        _cached(),
      ]);
      final container = start(service);
      expect(await settle(container), UpdatePrompt.required);

      expect(await reread(container), UpdatePrompt.required);
      expect(service.calls, 2);
      expect(
        container.read(appConfigProvider).value?.source,
        AppConfigSource.cache,
      );
    });

    test('a failed re-read does not lift a block', () async {
      final service = _FakeConfigService([
        _network(android: _blocking),
        const AppConfigUnavailableException(),
      ]);
      final container = start(service);
      expect(await settle(container), UpdatePrompt.required);

      expect(await reread(container), UpdatePrompt.required);
      expect(container.read(appConfigProvider).hasError, isTrue);
    });

    test('a block stays while a re-read is still on its way', () async {
      final pending = Completer<AppConfig>();
      final container = start(
        _FakeConfigService([_network(android: _blocking), pending]),
      );
      expect(await settle(container), UpdatePrompt.required);

      container.invalidate(appConfigProvider);
      await pumpEventQueue();
      expect(container.read(appConfigProvider).isLoading, isTrue);
      expect(container.read(updatePromptProvider), UpdatePrompt.required);

      pending.complete(_cached());
      expect(await settle(container), UpdatePrompt.required);
    });

    test('a fresh answer that the version is fine lifts the block', () async {
      final container = start(
        _FakeConfigService([_network(android: _blocking), _network()]),
      );
      expect(await settle(container), UpdatePrompt.required);

      expect(await reread(container), UpdatePrompt.none);
    });

    test('a fresh answer can block after a fine one', () async {
      final container = start(
        _FakeConfigService([_network(), _network(android: _blocking)]),
      );
      expect(await settle(container), UpdatePrompt.none);

      expect(await reread(container), UpdatePrompt.required);
    });

    test('a cached answer at launch never prompts', () async {
      final container = start(
        _FakeConfigService([
          _cached(android: const UpdatePolicy(minimum: '9.9.9')),
        ]),
      );
      expect(await settle(container), UpdatePrompt.none);
    });

    test('a failed fetch at launch never prompts', () async {
      final container = start(
        _FakeConfigService([const AppConfigUnavailableException()]),
      );
      expect(await settle(container), UpdatePrompt.none);
    });

    test('an installed version it cannot read never prompts', () async {
      final container = start(
        _FakeConfigService([
          _network(android: const UpdatePolicy(minimum: '9.9.9')),
        ]),
        installedVersion: () async => throw Exception('no package info'),
      );
      expect(await settle(container), UpdatePrompt.none);
    });

    test('platforms other than iOS and Android never prompt', () async {
      final container = start(
        _FakeConfigService([
          _network(
            android: const UpdatePolicy(minimum: '9.9.9'),
            ios: const UpdatePolicy(minimum: '9.9.9'),
          ),
        ]),
        platform: null,
      );
      expect(await settle(container), UpdatePrompt.none);
    });

    test('snooze hides the recommendation and is stored', () async {
      final container = start(
        _FakeConfigService([_network(android: _nudging)]),
        installed: '2.4.0',
      );
      expect(await settle(container), UpdatePrompt.recommended);

      await container.read(updatePromptProvider.notifier).snooze();

      expect(container.read(updatePromptProvider), UpdatePrompt.none);
      final stored = await UpdateSnoozeStore().read();
      expect(stored?.version, '2.4.1');
      expect(stored?.dismissedAt, now);
    });

    test('a snoozed recommendation stays hidden on a fresh re-read, and a '
        'higher one is a new reason to ask', () async {
      final container = start(
        _FakeConfigService([
          _network(android: _nudging),
          _network(android: _nudging),
          _network(android: const UpdatePolicy(recommended: '2.4.2')),
        ]),
        installed: '2.4.0',
      );
      expect(await settle(container), UpdatePrompt.recommended);
      await container.read(updatePromptProvider.notifier).snooze();

      expect(await reread(container), UpdatePrompt.none);
      expect(await reread(container), UpdatePrompt.recommended);
    });

    test('a snooze stored on an earlier launch hides the same recommendation '
        'for three days', () async {
      Future<UpdatePrompt> launchSnoozedAgo(Duration ago) async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'update_snooze_version': '2.4.1',
          'update_snooze_at': now.subtract(ago).millisecondsSinceEpoch,
        });
        final container = start(
          _FakeConfigService([_network(android: _nudging)]),
          installed: '2.4.0',
        );
        return settle(container);
      }

      expect(
        await launchSnoozedAgo(const Duration(days: 2)),
        UpdatePrompt.none,
      );
      expect(
        await launchSnoozedAgo(const Duration(days: 3)),
        UpdatePrompt.recommended,
      );
    });

    test('waits for the stored snooze before nudging, so a snoozed nudge '
        'never flashes up at launch', () async {
      final store = _SlowSnoozeStore();
      final container = start(
        _FakeConfigService([_network(android: _nudging)]),
        installed: '2.4.0',
        snoozeStore: store,
      );
      final seen = <UpdatePrompt>[];
      container.listen(updatePromptProvider, (_, next) => seen.add(next));
      expect(await settle(container), UpdatePrompt.none);

      store.reading.complete(UpdateSnooze(version: '2.4.1', dismissedAt: now));
      await pumpEventQueue();

      expect(container.read(updatePromptProvider), UpdatePrompt.none);
      expect(seen, isNot(contains(UpdatePrompt.recommended)));
    });

    test('a stored snooze never hides a block', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'update_snooze_version': '2.4.1',
        'update_snooze_at': now.millisecondsSinceEpoch,
      });
      final container = start(
        _FakeConfigService([
          _network(
            android: const UpdatePolicy(minimum: '2.4.0', recommended: '2.4.1'),
          ),
        ]),
      );
      expect(await settle(container), UpdatePrompt.required);
    });

    test('snooze cannot get past a block', () async {
      final container = start(
        _FakeConfigService([
          _network(
            android: const UpdatePolicy(minimum: '2.4.0', recommended: '2.4.1'),
          ),
        ]),
      );
      expect(await settle(container), UpdatePrompt.required);

      await container.read(updatePromptProvider.notifier).snooze();

      expect(container.read(updatePromptProvider), UpdatePrompt.required);
      expect(await UpdateSnoozeStore().read(), isNull);
    });

    test('snooze without a fresh recommendation stores nothing', () async {
      final container = start(_FakeConfigService([_cached()]));
      expect(await settle(container), UpdatePrompt.none);

      await container.read(updatePromptProvider.notifier).snooze();

      expect(container.read(updatePromptProvider), UpdatePrompt.none);
      expect(await UpdateSnoozeStore().read(), isNull);
    });
  });

  group('updatePlatformProvider', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    TargetPlatform? platformOn(TargetPlatform platform) {
      debugDefaultTargetPlatformOverride = platform;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      return container.read(updatePlatformProvider);
    }

    test('is the platform on iOS and Android, and null elsewhere', () {
      expect(platformOn(TargetPlatform.iOS), TargetPlatform.iOS);
      expect(platformOn(TargetPlatform.android), TargetPlatform.android);
      expect(platformOn(TargetPlatform.macOS), isNull);
      expect(platformOn(TargetPlatform.windows), isNull);
      expect(platformOn(TargetPlatform.linux), isNull);
      expect(platformOn(TargetPlatform.fuchsia), isNull);
    });
  });

  group('appConfigResumeRefreshProvider', () {
    final binding = TestWidgetsFlutterBinding.instance;

    setUp(() {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(
        () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
      );
    });

    /// Sends the app to the background and back.
    void backgroundAndBack() {
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        binding.handleAppLifecycleStateChanged(state);
      }
    }

    /// Sends the app to the background and back, then lets the re-fetch that
    /// may follow arrive.
    Future<void> backgroundAndResume(ProviderContainer container) async {
      backgroundAndBack();
      await settle(container);
    }

    ProviderContainer startRefreshing(_FakeConfigService service) {
      final container = start(service);
      container.listen(appConfigResumeRefreshProvider, (_, _) {});
      return container;
    }

    test(
      'does not re-fetch on a resume within an hour of a fresh answer',
      () async {
        final service = _FakeConfigService([_network()]);
        final container = startRefreshing(service);
        await settle(container);
        expect(service.calls, 1);

        now = now.add(const Duration(minutes: 59));
        await backgroundAndResume(container);
        expect(service.calls, 1);
      },
    );

    test('re-fetches on a resume an hour after a fresh answer, and that '
        'answer can block', () async {
      final service = _FakeConfigService([
        _network(),
        _network(android: _blocking),
      ]);
      final container = startRefreshing(service);
      expect(await settle(container), UpdatePrompt.none);

      now = now.add(const Duration(hours: 1));
      await backgroundAndResume(container);
      expect(service.calls, 2);
      expect(container.read(updatePromptProvider), UpdatePrompt.required);
    });

    test('counts the hour from the latest fresh answer', () async {
      final service = _FakeConfigService([_network()]);
      final container = startRefreshing(service);
      await settle(container);

      now = now.add(const Duration(hours: 1));
      await backgroundAndResume(container);
      expect(service.calls, 2);

      now = now.add(const Duration(minutes: 30));
      await backgroundAndResume(container);
      expect(service.calls, 2);
    });

    test('a cached answer does not count as a fresh one', () async {
      final service = _FakeConfigService([_network(), _cached()]);
      final container = startRefreshing(service);
      await settle(container);

      now = now.add(const Duration(hours: 1));
      await backgroundAndResume(container);
      expect(service.calls, 2);

      now = now.add(const Duration(minutes: 1));
      await backgroundAndResume(container);
      expect(service.calls, 3);
    });

    test('re-fetches on every resume until a fresh answer arrives', () async {
      final service = _FakeConfigService([
        const AppConfigUnavailableException(),
        _cached(),
        _network(),
      ]);
      final container = startRefreshing(service);
      await settle(container);

      await backgroundAndResume(container);
      expect(service.calls, 2);
      await backgroundAndResume(container);
      expect(service.calls, 3);
      await backgroundAndResume(container);
      expect(service.calls, 3);
    });

    test('stops listening for resumes once disposed', () async {
      // A listener still registered reads the clock on every resume, so the
      // clock tells whether anything is still listening.
      var clockReads = 0;
      final container = ProviderContainer(
        overrides: [
          appConfigServiceProvider.overrideWithValue(
            _FakeConfigService([_network()]),
          ),
          updateClockProvider.overrideWithValue(() {
            clockReads++;
            return now;
          }),
        ],
      );
      container.listen(appConfigResumeRefreshProvider, (_, _) {});
      await pumpEventQueue();
      final readsBeforeResume = clockReads;

      backgroundAndBack();
      await pumpEventQueue();
      expect(clockReads, greaterThan(readsBeforeResume));

      container.dispose();
      final readsWhenDisposed = clockReads;
      backgroundAndBack();
      await pumpEventQueue();
      expect(clockReads, readsWhenDisposed);
    });
  });

  group('UpdateSnoozeStore', () {
    test('reads back what it wrote', () async {
      final store = UpdateSnoozeStore();
      expect(await store.read(), isNull);

      await store.write(UpdateSnooze(version: '2.4.1', dismissedAt: now));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('update_snooze_version'), '2.4.1');
      expect(prefs.getInt('update_snooze_at'), now.millisecondsSinceEpoch);
      final read = await store.read();
      expect(read?.version, '2.4.1');
      expect(read?.dismissedAt, now);
    });

    test('reads a half-written or unreadable snooze as none', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'update_snooze_version': '2.4.1',
      });
      expect(await UpdateSnoozeStore().read(), isNull);

      SharedPreferences.setMockInitialValues(<String, Object>{
        'update_snooze_version': 241,
        'update_snooze_at': 'yesterday',
      });
      expect(await UpdateSnoozeStore().read(), isNull);
    });
  });
}
