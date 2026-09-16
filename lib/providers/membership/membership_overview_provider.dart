import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/print_migration.dart';
import '../../data/models/membership_overview.dart';
import '../../data/services/membership_api_client.dart';
import '../auth/auth_provider.dart';

final membershipApiClientProvider = Provider<MembershipApiClient>(
  (ref) => MembershipApiClient(),
);

/// Whose membership to show: the signed-in account once the session has
/// resolved, or null. Separate so tests can pin a student.
final membershipUserIdProvider = Provider<String?>((ref) {
  return ref.watch(
    authStateProvider.select(
      (state) => state.isLoading ? null : state.signedInUserId,
    ),
  );
});

/// How old a verification may get before returning to the app re-checks it.
const membershipRecheckAfter = Duration(minutes: 10);

/// How long a cached "member" still counts for member-only products when a
/// fresh check cannot be made.
const membershipCacheTrust = Duration(hours: 24);

/// The signed-in student's membership, verified against 24SevenOffice by the
/// server.
///
/// Verified when a student is known (so a cold launch checks without any
/// membership screen open), and again when the app returns to the foreground
/// after [membershipRecheckAfter], or immediately after the student went to
/// biso.no to link their BI account. The last verified overview is kept per
/// student so an offline launch can still show it, marked [MembershipOverview.fromCache].
class MembershipOverviewNotifier extends AsyncNotifier<MembershipOverview?> {
  static String cacheKey(String userId) => 'membership_overview_v1_$userId';

  bool _linkStarted = false;

  @override
  Future<MembershipOverview?> build() async {
    final userId = ref.watch(membershipUserIdProvider);

    final lifecycle = AppLifecycleListener(
      onResume: () => unawaited(_onResume()),
    );
    ref.onDispose(lifecycle.dispose);

    if (userId == null) return null;
    return _load(userId, refresh: false);
  }

  /// Re-checks with the server. [force] asks it to bypass its own cache
  /// (it still re-checks 24SevenOffice at most once a minute).
  Future<void> refresh({bool force = true}) async {
    final userId = ref.read(membershipUserIdProvider);
    if (userId == null) return;
    state = const AsyncLoading<MembershipOverview?>().copyWithPrevious(state);
    state = await AsyncValue.guard(() => _load(userId, refresh: force));
  }

  /// The student is leaving for biso.no to link their BI account; the next
  /// return to the app re-checks straight away.
  void noteLinkStarted() => _linkStarted = true;

  Future<void> _onResume() async {
    if (_linkStarted) {
      _linkStarted = false;
      await refresh(force: true);
      return;
    }
    if (state.isLoading) return;
    final current = state.valueOrNull;
    final stale =
        current == null ||
        current.fromCache ||
        DateTime.now().difference(current.checkedAt) > membershipRecheckAfter;
    if (stale) {
      await refresh(force: false);
    }
  }

  Future<MembershipOverview?> _load(
    String userId, {
    required bool refresh,
  }) async {
    try {
      final fresh = await ref
          .read(membershipApiClientProvider)
          .fetchOverview(refresh: refresh);
      if (fresh.state == MembershipGateState.checkUnavailable) {
        // The server could not verify right now. The last verified answer is
        // more useful to the student than "unavailable", as long as it is
        // shown as cached.
        return await _readCache(userId) ?? fresh;
      }
      await _writeCache(userId, fresh);
      return fresh;
    } catch (error) {
      logPrint('🎫 Membership check failed: $error');
      final cached = await _readCache(userId);
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<MembershipOverview?> _readCache(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(cacheKey(userId));
      if (raw == null) return null;
      return MembershipOverview.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
        fromCache: true,
      );
    } catch (error) {
      logPrint('🎫 Could not read the cached membership: $error');
      return null;
    }
  }

  Future<void> _writeCache(String userId, MembershipOverview overview) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey(userId), jsonEncode(overview.toJson()));
    } catch (error) {
      logPrint('🎫 Could not cache the membership: $error');
    }
  }
}

final membershipOverviewProvider =
    AsyncNotifierProvider<MembershipOverviewNotifier, MembershipOverview?>(
      MembershipOverviewNotifier.new,
    );

/// Whether the student has a valid membership, for presentation such as
/// member-only products. A cached answer counts for [membershipCacheTrust];
/// prices are always decided by the server.
final hasValidMembershipProvider = Provider<bool>((ref) {
  final overview = ref.watch(membershipOverviewProvider).valueOrNull;
  if (overview == null || !overview.isMember) return false;
  if (!overview.fromCache) return true;
  return DateTime.now().difference(overview.checkedAt) <= membershipCacheTrust;
});
