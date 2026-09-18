import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/member_pass.dart';
import '../../data/services/member_pass_api_client.dart';
import '../../data/services/screen_presentation.dart';
import '../../data/services/wallet_channel.dart';
import '../membership/membership_overview_provider.dart';
import 'member_pass_session.dart';

final memberPassApiProvider = Provider<MemberPassApi>(
  (ref) => MemberPassApiClient(),
);

final walletChannelProvider = Provider<WalletChannel>(
  (ref) => const WalletChannel(),
);

final canAddApplePassesProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(walletChannelProvider).canAddPasses(),
);

/// The local clock in Unix milliseconds. Separate so tests can move time.
final memberPassClockProvider = Provider<int Function()>(
  (ref) =>
      () => DateTime.now().millisecondsSinceEpoch,
);

/// Fires when a network interface changes. Only a hint to fetch: a changed
/// interface does not mean the internet works.
final connectivityChangesProvider = Provider<Stream<Object?>>(
  (ref) => Connectivity().onConnectivityChanged,
);

final screenPresentationProvider = Provider<ScreenPresentation>(
  (ref) => DeviceScreenPresentation(),
);

final memberPassProvider =
    NotifierProvider.autoDispose<MemberPassNotifier, MemberPassView>(
      MemberPassNotifier.new,
    );

/// The signed-in member's live pass.
///
/// Codes live only here, in memory. The provider disposes when no screen
/// watches or [hold]s it, and the codes go with it.
class MemberPassNotifier extends AutoDisposeNotifier<MemberPassView> {
  static const tick = Duration(seconds: 1);

  MemberPassSession _session = MemberPassSession();
  bool _inFlight = false;
  int? _lastAttemptMs;

  /// Bumped on every build and dispose, so a fetch started for an earlier
  /// account or lifetime never writes into this one.
  int _generation = 0;

  int _now() => ref.read(memberPassClockProvider)();

  @override
  MemberPassView build() {
    _generation++;
    _session = MemberPassSession();
    _inFlight = false;
    _lastAttemptMs = null;
    ref.onDispose(() => _generation++);

    if (ref.watch(membershipUserIdProvider) == null) {
      _session.applyUnauthorized();
      return _session.view(_now());
    }

    final lifecycle = AppLifecycleListener(onResume: onAppResumed);
    final changes = ref
        .watch(connectivityChangesProvider)
        .listen((_) => onConnectivityChanged());
    final ticker = Timer.periodic(tick, (_) => _onTick());
    ref.onDispose(() {
      lifecycle.dispose();
      changes.cancel();
      ticker.cancel();
    });

    Future.microtask(_fetch);
    return _session.view(_now());
  }

  /// Keeps the codes alive while a route that shows them is open.
  KeepAliveLink hold() => ref.keepAlive();

  Future<void> retry() => _fetch();

  void onAppResumed() => unawaited(_fetch());

  void onConnectivityChanged() => unawaited(_fetch());

  void _onTick() {
    final now = _now();
    if (_session.shouldRetry(
      now,
      lastAttemptMs: _lastAttemptMs,
      inFlight: _inFlight,
    )) {
      unawaited(_fetch());
    }
    state = _session.view(now, fetching: _inFlight);
  }

  Future<void> _fetch() async {
    if (_inFlight) return;
    final generation = _generation;
    final api = ref.read(memberPassApiProvider);
    _inFlight = true;
    _lastAttemptMs = _now();
    state = _session.view(_lastAttemptMs!, fetching: true);

    MemberPassResponse? response;
    MemberPassApiException? failure;
    try {
      response = await api.fetchPass();
    } on MemberPassApiException catch (error) {
      failure = error;
    } catch (_) {
      failure = const MemberPassApiException(MemberPassApiException.network);
    }
    if (generation != _generation) return;

    _inFlight = false;
    final now = _now();
    if (response != null) {
      _session.apply(response, now);
    } else if (failure!.isUnauthorized) {
      _session.applyUnauthorized();
    } else if (failure.statusCode == null) {
      _session.applyNetworkFailure(now);
    } else {
      _session.applyServerFailure(now);
    }
    state = _session.view(now);
  }
}
