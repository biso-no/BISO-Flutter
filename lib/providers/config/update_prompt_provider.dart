import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/models/app_config.dart';
import '../../data/models/update_decision.dart';
import '../../data/models/update_policy.dart';
import '../../data/services/update_snooze_store.dart';
import 'app_config_provider.dart';

/// How long a fresh config answer is trusted before a resume asks again.
const appConfigResumeRecheckInterval = Duration(hours: 1);

final updateSnoozeStoreProvider = Provider<UpdateSnoozeStore>(
  (_) => UpdateSnoozeStore(),
);

/// The version of the app that is running, as `major.minor.patch` — the
/// build number is not part of it and is never compared.
final installedVersionProvider = FutureProvider<String>((_) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

/// The platform whose update policy applies to this device: iOS or Android,
/// or `null` anywhere else (the web included), which never sees a prompt.
/// BISO only ships through the App Store and Google Play, so there is no
/// store to send anyone else to.
final updatePlatformProvider = Provider<TargetPlatform?>((_) {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.android => defaultTargetPlatform,
    _ => null,
  };
});

final updateClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

final updatePromptProvider =
    NotifierProvider<UpdatePromptNotifier, UpdatePrompt>(
      UpdatePromptNotifier.new,
    );

/// What the app should say about updates right now: nothing, a dismissible
/// nudge ([UpdatePrompt.recommended]) or a full block
/// ([UpdatePrompt.required]).
///
/// Only a fresh answer can prompt. The state changes only when
/// `appConfigProvider` delivers a config fetched from the network in this
/// session — a cached config is up to an hour old and carries no policy, and
/// a fetch that failed says nothing about BISO's settings at all. Until a
/// fresh answer has arrived, and until the installed version is known, there
/// is no prompt.
///
/// A prompt already decided stays until a fresh answer changes it. A re-read
/// that is still loading, that failed, or that came back from the cache
/// leaves the state as it is, so a block survives a resume while offline
/// instead of lifting the moment the network drops. Only a fresh answer that
/// the installed version is fine lifts it.
class UpdatePromptNotifier extends Notifier<UpdatePrompt> {
  TargetPlatform? _platform;

  /// The last config fetched from the network in this session.
  AppConfig? _fresh;
  String? _installedVersion;
  UpdateSnooze? _snooze;
  bool _snoozeKnown = false;

  /// Bumped on every build and dispose, so a snooze read started for an
  /// earlier build never writes into this one.
  int _generation = 0;

  @override
  UpdatePrompt build() {
    final generation = ++_generation;
    ref.onDispose(() => _generation++);
    _fresh = null;
    _installedVersion = null;
    _snooze = null;
    _snoozeKnown = false;

    _platform = ref.watch(updatePlatformProvider);
    if (_platform == null) return UpdatePrompt.none;

    final config = ref.listen(appConfigProvider, (_, next) {
      if (_takeConfig(next)) _publish();
    });
    final installed = ref.listen(installedVersionProvider, (_, next) {
      if (_takeInstalledVersion(next)) _publish();
    });
    _takeConfig(config.read());
    _takeInstalledVersion(installed.read());
    unawaited(_loadSnooze(ref.read(updateSnoozeStoreProvider), generation));

    return _decide() ?? UpdatePrompt.none;
  }

  /// Hides the current recommendation for [updateSnoozeDuration], on this
  /// device, across launches.
  ///
  /// Snoozes the version the last fresh answer recommends for this platform.
  /// A higher recommendation later is a new reason to ask and shows again.
  ///
  /// Does nothing during a block ([UpdatePrompt.required]): there is no way
  /// past the required screen, so nothing is stored and the block stays.
  Future<void> snooze() async {
    if (state == UpdatePrompt.required) return;

    final recommended = _fresh == null ? null : _policyOf(_fresh!).recommended;
    state = UpdatePrompt.none;
    if (recommended == null) return;

    final snooze = UpdateSnooze(
      version: recommended,
      dismissedAt: ref.read(updateClockProvider)(),
    );
    _snooze = snooze;
    _snoozeKnown = true;
    try {
      await ref.read(updateSnoozeStoreProvider).write(snooze);
    } catch (e) {
      // Dismissing still works for this session; the nudge returns next
      // launch.
      debugPrint('UpdatePromptNotifier: could not store the snooze: $e');
    }
  }

  /// Keeps [value] if it is a fresh config, reporting whether it did.
  bool _takeConfig(AsyncValue<AppConfig> value) {
    // A re-read in flight still holds the previous value, and a failed one
    // may too: neither is a new answer.
    if (value.isLoading || value.hasError) return false;
    final config = value.valueOrNull;
    if (config == null || config.source != AppConfigSource.network) {
      return false;
    }
    _fresh = config;
    return true;
  }

  bool _takeInstalledVersion(AsyncValue<String> value) {
    final version = value.valueOrNull;
    if (value.isLoading || value.hasError || version == null) return false;
    _installedVersion = version;
    return true;
  }

  Future<void> _loadSnooze(UpdateSnoozeStore store, int generation) async {
    UpdateSnooze? stored;
    try {
      stored = await store.read();
    } catch (e) {
      debugPrint('UpdatePromptNotifier: could not read the snooze: $e');
    }
    if (generation != _generation) return;
    // A snooze made while this was reading is newer than the stored one.
    _snooze ??= stored;
    _snoozeKnown = true;
    _publish();
  }

  void _publish() {
    final next = _decide();
    if (next != null) state = next;
  }

  /// The prompt everything known so far adds up to, or `null` while a fresh
  /// config, the installed version or the stored snooze is still missing.
  UpdatePrompt? _decide() {
    final config = _fresh;
    final installedVersion = _installedVersion;
    if (config == null || installedVersion == null || !_snoozeKnown) {
      return null;
    }
    return decideUpdate(
      installedVersion: installedVersion,
      policy: _policyOf(config),
      source: config.source,
      snooze: _snooze,
      now: ref.read(updateClockProvider)(),
    );
  }

  UpdatePolicy _policyOf(AppConfig config) => switch (_platform) {
    TargetPlatform.iOS => config.iosUpdates,
    TargetPlatform.android => config.androidUpdates,
    _ => UpdatePolicy.none,
  };
}

/// The device's network interfaces each time they change, starting with how
/// they are now. Separate so tests can drive it. Only a hint: an interface
/// coming up does not mean the internet works.
final connectivityResultsProvider = Provider<Stream<List<ConnectivityResult>>>(
  (_) => Connectivity().onConnectivityChanged,
);

/// Asks for the config again when the app comes back to the foreground, and
/// when the network comes back before the app has had a fresh answer.
///
/// A student who keeps the app open in the background for days would
/// otherwise never hear of a new minimum version. A resume asks at most once
/// per [appConfigResumeRecheckInterval], counted from the last fresh answer
/// this provider saw: a cached answer or a failed fetch does not count, so
/// after one of those the next resume asks again.
///
/// While the app is blocked ([UpdatePrompt.required]) every resume asks: a
/// block set by mistake and then cleared in the admin must lift when the
/// student next returns to the app, not an hour later.
///
/// A launch without the network leaves the app with no fresh answer, and so
/// with no prompt. When the network comes back it asks once, and again only
/// after the network has gone and come back once more.
///
/// Nothing asks while a fetch is already on its way. The re-read never lifts
/// a block by itself — see [UpdatePromptNotifier].
final appConfigResumeRefreshProvider = Provider<void>((ref) {
  final now = ref.watch(updateClockProvider);
  DateTime? lastFreshAnswer;

  ref.listen<AsyncValue<AppConfig>>(appConfigProvider, (_, next) {
    if (next.isLoading || next.hasError) return;
    if (next.valueOrNull?.source == AppConfigSource.network) {
      lastFreshAnswer = now();
    }
  }, fireImmediately: true);

  void refetch() {
    if (ref.read(appConfigProvider).isLoading) return;
    ref.invalidate(appConfigProvider);
  }

  void onResume() {
    final blocked = ref.read(updatePromptProvider) == UpdatePrompt.required;
    final last = lastFreshAnswer;
    if (!blocked &&
        last != null &&
        now().difference(last) < appConfigResumeRecheckInterval) {
      return;
    }
    refetch();
  }

  /// Whether the last report had a network, or `null` before the first one.
  bool? online;
  void onConnectivityChanged(List<ConnectivityResult> results) {
    final wasOnline = online;
    final isOnline = results.any((r) => r != ConnectivityResult.none);
    online = isOnline;
    final regained = wasOnline == false && isOnline;
    if (regained && lastFreshAnswer == null) refetch();
  }

  final lifecycle = AppLifecycleListener(onResume: onResume);
  ref.onDispose(lifecycle.dispose);
  final connectivity = ref
      .watch(connectivityResultsProvider)
      .listen(
        onConnectivityChanged,
        // Without connectivity reports the resume re-check still works.
        onError: (Object e) =>
            debugPrint('appConfigResumeRefresh: no connectivity reports: $e'),
      );
  ref.onDispose(connectivity.cancel);
});
