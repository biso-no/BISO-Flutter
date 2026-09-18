import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/member_pass.dart';
import '../../data/services/member_pass_api_client.dart';
import '../membership/membership_overview_provider.dart';
import 'member_pass_provider.dart';

/// Whether the signed-in user may scan passes, as the server says.
sealed class ScannerAccessState extends Equatable {
  const ScannerAccessState();

  @override
  List<Object?> get props => [];
}

class ScannerGranted extends ScannerAccessState {
  const ScannerGranted(this.access);

  final ScannerAccess access;

  @override
  List<Object?> get props => [access];
}

/// No active grant (or the route is not deployed yet).
class ScannerDenied extends ScannerAccessState {
  const ScannerDenied();
}

class ScannerSignedOut extends ScannerAccessState {
  const ScannerSignedOut();
}

/// The server has no pass secret configured.
class ScannerNotConfigured extends ScannerAccessState {
  const ScannerNotConfigured();
}

/// The server could not be asked. Never cached.
class ScannerCheckFailed extends ScannerAccessState {
  const ScannerCheckFailed();
}

final scannerAccessProvider =
    AsyncNotifierProvider<ScannerAccessNotifier, ScannerAccessState>(
      ScannerAccessNotifier.new,
    );

/// The scanner grant, kept in memory for [maxAge] and re-checked on resume.
/// `/scan` re-checks the grant on every scan, so this only decides what to
/// show.
class ScannerAccessNotifier extends AsyncNotifier<ScannerAccessState> {
  static const maxAge = Duration(minutes: 5);

  int? _checkedAtMs;
  int _generation = 0;

  int _now() => ref.read(memberPassClockProvider)();

  @override
  Future<ScannerAccessState> build() async {
    final generation = ++_generation;
    _checkedAtMs = null;
    final lifecycle = AppLifecycleListener(
      onResume: () => unawaited(ensureFresh()),
    );
    ref.onDispose(() {
      _generation++;
      lifecycle.dispose();
    });
    if (ref.watch(membershipUserIdProvider) == null) {
      return const ScannerSignedOut();
    }
    return _check(generation);
  }

  /// Asks the server again if the answer is older than [maxAge], failed, or
  /// [force] is set. The previous answer stays visible meanwhile.
  ///
  /// Like the pass, only a definitive answer replaces a grant: when the
  /// server cannot be asked, the scanner keeps working and the next call asks
  /// again.
  Future<void> ensureFresh({bool force = false}) async {
    if (ref.read(membershipUserIdProvider) == null) return;
    if (state.isLoading) return;
    final checkedAt = _checkedAtMs;
    final fresh =
        checkedAt != null &&
        _now() - checkedAt < maxAge.inMilliseconds &&
        state.valueOrNull is! ScannerCheckFailed;
    if (fresh && !force) return;

    final generation = _generation;
    final previous = state.valueOrNull;
    state = const AsyncLoading<ScannerAccessState>().copyWithPrevious(state);
    final next = await _check(generation);
    if (generation != _generation) return;
    state = AsyncData(
      next is ScannerCheckFailed && previous is ScannerGranted
          ? previous
          : next,
    );
  }

  Future<ScannerAccessState> _check(int generation) async {
    final startedAt = _now();
    final api = ref.read(memberPassApiProvider);
    ScannerAccessState result;
    try {
      result = ScannerGranted(await api.fetchScannerAccess());
    } on MemberPassApiException catch (error) {
      if (error.isUnauthorized) {
        result = const ScannerSignedOut();
      } else if (error.isForbidden || error.isNotFound) {
        result = const ScannerDenied();
      } else if (error.isNotConfigured) {
        result = const ScannerNotConfigured();
      } else {
        result = const ScannerCheckFailed();
      }
    } catch (_) {
      result = const ScannerCheckFailed();
    }
    if (generation == _generation) {
      // A check that could not be made leaves nothing fresh.
      _checkedAtMs = result is ScannerCheckFailed ? null : startedAt;
    }
    return result;
  }
}
