import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_notification_model.dart';
import '../../data/services/notification_inbox_service.dart';
import '../../data/services/notification_service.dart';
import '../auth/auth_provider.dart';
import '../ui/locale_provider.dart';

// Provider for the notification service
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

// Provider for the inbox service (announcements + user_notifications)
final notificationInboxServiceProvider = Provider<NotificationInboxService>((
  ref,
) {
  return NotificationInboxService();
});

// Provider for checking if notifications are enabled
final notificationStatusProvider = FutureProvider<bool>((ref) async {
  final service = ref.read(notificationServiceProvider);
  return await service.areNotificationsEnabled();
});

// Provider for getting chat notification preference
final chatNotificationPreferenceProvider = FutureProvider<bool>((ref) async {
  final service = ref.read(notificationServiceProvider);
  return await service.getChatNotificationPreference();
});

// State notifier for managing notification preferences
class NotificationPreferencesNotifier
    extends StateNotifier<AsyncValue<Map<String, bool>>> {
  final NotificationService _notificationService;

  NotificationPreferencesNotifier(this._notificationService)
    : super(const AsyncValue.loading()) {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      state = const AsyncValue.loading();

      // Load chat notifications preference
      final chatEnabled = await _notificationService
          .getChatNotificationPreference();

      // Await the load: reading the in-memory map directly renders hardcoded
      // defaults over the student's saved choices on a cold start.
      //
      // A failed read is caught here, separately from the block below, and
      // must not take down `chat_notifications` above (which loaded fine) —
      // default to empty rather than fabricating topic flags that could
      // later be persisted over the student's real saved intent.
      Map<String, bool> topicSubscriptions;
      try {
        topicSubscriptions = await _notificationService.loadTopicIntent();
      } catch (error) {
        debugPrint(
          'NotificationPreferencesNotifier: loadTopicIntent failed: $error',
        );
        topicSubscriptions = const <String, bool>{};
      }

      // Combine all preferences
      final allPreferences = {
        'chat_notifications': chatEnabled,
        ...topicSubscriptions,
      };

      state = AsyncValue.data(allPreferences);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> updateChatNotifications(bool enabled) async {
    try {
      await _notificationService.updateChatNotificationPreference(enabled);

      // Update state
      final currentData = state.value ?? {};
      state = AsyncValue.data({...currentData, 'chat_notifications': enabled});
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> updateTopicSubscription(String topicId, bool enabled) async {
    try {
      await _notificationService.updateTopicSubscription(topicId, enabled);

      // Update state
      final currentData = state.value ?? {};
      state = AsyncValue.data({...currentData, topicId: enabled});
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> refresh() async {
    await _loadPreferences();
  }
}

// Provider for notification preferences state notifier
final notificationPreferencesProvider =
    StateNotifierProvider<
      NotificationPreferencesNotifier,
      AsyncValue<Map<String, bool>>
    >((ref) {
      final service = ref.read(notificationServiceProvider);
      return NotificationPreferencesNotifier(service);
    });

/// The student's topic intent, and the only UI entry point for changing it.
///
/// Every change writes intent first, then reconciles this device's Appwrite
/// subscriptions to match. The two can fail independently, and are reported
/// differently: a failed *save* reverts the optimistic switch, because the
/// student's choice was never actually recorded. A failed or partial
/// *reconcile* leaves the switch as set — the intent is genuinely saved, and
/// will be honoured next time reconcile runs — and instead reports what
/// happened on this device via a [ReconcileOutcome] so the caller can decide
/// whether the student needs telling (see [setTopic]).
///
/// The state stays `AsyncValue.data` throughout a save failure —
/// deliberately. Riverpod flushes at most one notification per event-loop
/// turn, so assigning `data(current)` and then `error(...)` would render only
/// the error: the revert would never be seen, and the whole card would be
/// replaced by an error message that hides all four switches. Since this
/// provider is not autoDispose, nothing short of an app restart would bring
/// them back.
class TopicIntentNotifier extends StateNotifier<AsyncValue<Map<String, bool>>> {
  TopicIntentNotifier(this._service, this._campusId)
    : super(const AsyncValue.loading()) {
    _load();
  }

  final NotificationService _service;
  final String? _campusId;

  /// Serialises the network side of [setTopic].
  ///
  /// Two quick taps each call `setTopic`, and without this, both calls'
  /// `saveTopicIntent` requests fire at once — whichever one's response
  /// arrives *last* wins on the server, even if it is the older, staler one,
  /// silently resurrecting a setting the student just turned off. Chaining
  /// each save onto this tail forces them to run one at a time, in the order
  /// [setTopic] was called.
  ///
  /// Every link swallows its own outcome (`.then((_) {}, onError: (_) {})`)
  /// before being stored back here, so one call's failure can never leave
  /// this future permanently rejected and wedge every *later* call's save
  /// from ever running.
  Future<void> _pendingSave = Future<void>.value();

  Future<void> _load() async {
    try {
      final intent = await _service.loadTopicIntent();
      if (mounted) state = AsyncValue.data(intent);
    } catch (error, stackTrace) {
      debugPrint('TopicIntentNotifier load failed: $error');
      if (mounted) state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Saves [topicId]'s new [enabled] value, then reconciles this device.
  ///
  /// Returns `null` when the save itself failed — the switch is reverted, and
  /// the caller should tell the student nothing was recorded, exactly as
  /// before. Otherwise the intent is genuinely saved: the switch stays as set
  /// regardless of what follows, and the returned [ReconcileOutcome] tells
  /// the caller what happened to *this device's* subscriptions, so it can
  /// decide whether the student needs telling (see `settings_screen.dart`).
  ///
  /// The optimistic switch flip happens here, synchronously, so two quick
  /// taps both respond immediately — disabling the controls while a save is
  /// in flight was rejected as a UX regression. Only the actual network
  /// save is queued (see [_pendingSave]); [_commit] does the merging, once
  /// it is this call's turn to run.
  Future<ReconcileOutcome?> setTopic(String topicId, bool enabled) {
    final seed = state.value;
    if (seed == null) return Future<ReconcileOutcome?>.value();
    final previousValue = seed[topicId] ?? false;

    // Optimistic, so the switch responds immediately.
    state = AsyncValue.data(<String, bool>{...seed, topicId: enabled});

    final result = _pendingSave.then(
      (_) => _commit(topicId, enabled, previousValue),
    );
    _pendingSave = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Runs one topic change's save + reconcile. Always executes strictly
  /// after every previously queued change has finished, via [_pendingSave].
  ///
  /// Reads [state] fresh, right here, rather than trusting a snapshot
  /// [setTopic] captured back when it was called: an earlier queued change
  /// can fail and revert while this one is still waiting its turn (see the
  /// catch block below), and this merge must build on that corrected value —
  /// resolving the resurrection race in [setTopic]'s doc comment is only
  /// half the fix if a stale merge base can still smuggle a failed change
  /// back in through the *next* call's save.
  Future<ReconcileOutcome?> _commit(
    String topicId,
    bool enabled,
    bool previousValue,
  ) async {
    final base = state.value;
    if (base == null) return null;
    final updated = <String, bool>{...base, topicId: enabled};

    try {
      await _service.saveTopicIntent(updated);
    } catch (error) {
      debugPrint(
        'TopicIntentNotifier.setTopic($topicId) failed to save: $error',
      );
      // Revert only this call's own key, on top of whatever state looks
      // like right now — not `base`, which is this same value (the
      // optimistic flip already happened before this ran) and not `updated`
      // — either would either no-op or stomp a different key that another,
      // still-in-flight call has since changed.
      if (mounted) {
        final latest = state.value ?? base;
        state = AsyncValue.data(<String, bool>{
          ...latest,
          topicId: previousValue,
        });
      }
      return null;
    }

    // Intent is saved from here on. Whatever reconcile() does or doesn't
    // manage on this device, the switch must not revert — the student's
    // choice is real, saved, and will be applied the next time reconcile
    // runs, so reverting it here would be a lie.
    //
    // Merged against the latest state, exactly like the revert branch above
    // — not written as `updated` outright, which is this call's own merge,
    // frozen at the top of this function. A still-queued call for a
    // *different* topic can have optimistically changed state while this
    // call's save was in flight, and overwriting with that stale snapshot
    // would revert the newer change until its own commit eventually runs and
    // corrects it — a visible flicker of a switch un-toggling itself for no
    // reason a student caused.
    if (mounted) {
      final latest = state.value ?? updated;
      state = AsyncValue.data(<String, bool>{...latest, topicId: enabled});
    }

    try {
      return await _service.reconcile(campusId: _campusId);
    } catch (error) {
      // reconcile() is designed to report failure via ReconcileOutcome
      // rather than throw; this is a last-resort net for anything
      // unanticipated, so a stray exception still can't be mistaken for the
      // save having failed.
      debugPrint(
        'TopicIntentNotifier.setTopic($topicId) reconcile failed: $error',
      );
      return ReconcileOutcome.unavailable;
    }
  }

  Future<void> refresh() => _load();
}

/// Rebuilds when the signed-in student or their home campus changes, so a
/// campus move resubscribes this device.
final topicIntentProvider =
    StateNotifierProvider<TopicIntentNotifier, AsyncValue<Map<String, bool>>>((
      ref,
    ) {
      final service = ref.watch(notificationServiceProvider);
      final campusId = ref.watch(
        authStateProvider.select((state) => state.user?.campusId),
      );
      return TopicIntentNotifier(service, campusId);
    });

// ---------------------------------------------------------------------------
// In-app notification inbox
// ---------------------------------------------------------------------------

/// Immutable state for the notification inbox.
class NotificationInboxState {
  final List<AppNotification> items;
  final bool isLoading;
  final String? error;

  const NotificationInboxState({
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  int get unreadCount => items.where((item) => !item.read).length;

  NotificationInboxState copyWith({
    List<AppNotification>? items,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return NotificationInboxState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class NotificationInboxNotifier extends StateNotifier<NotificationInboxState> {
  final NotificationInboxService _service;
  final NotificationService _notificationService;
  final String? _userId;
  final String _locale;
  final String? _campusId;

  RealtimeSubscription? _subscription;
  StreamSubscription<void>? _foregroundSubscription;

  NotificationInboxNotifier(
    this._service, {
    required NotificationService notificationService,
    required String? userId,
    required String locale,
    required String? campusId,
  }) : _notificationService = notificationService,
       _userId = userId,
       _locale = locale,
       _campusId = campusId,
       super(const NotificationInboxState()) {
    if (_userId != null && _userId.isNotEmpty) {
      load();
      _subscription = _service.subscribe(onChange: refresh);
      _foregroundSubscription = _notificationService.onForegroundMessage.listen(
        (_) => refresh(),
      );
    }
  }

  /// The student's logical topic intent, or an empty map when the read
  /// itself fails.
  ///
  /// Empty means "show everything" to [NotificationInboxService.fetchInbox]
  /// (nothing to opt out of), which is the safe direction to fail in here: an
  /// inbox that occasionally shows a topic the student muted is a nuisance, an
  /// inbox that fails to load at all because a preferences read hiccuped is
  /// worse. Contrast [TopicIntentNotifier], where the same failure surfaces as
  /// an error state instead — there, a fabricated map risks being persisted
  /// back over the student's real saved intent, which showing-too-much here
  /// never does.
  Future<Map<String, bool>> _loadTopicIntentOrShowAll() async {
    try {
      return await _notificationService.loadTopicIntent();
    } catch (e) {
      debugPrint('NotificationInboxNotifier: loadTopicIntent failed: $e');
      return const <String, bool>{};
    }
  }

  Future<void> load() async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) {
      state = const NotificationInboxState();
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // The inbox filters by logical topic intent (news/events/jobs/shop),
      // not the legacy per-device `topic_subscriptions` map that
      // `ensureTopicSubscriptionsLoaded()` reads — that map is keyed by the
      // pre-migration topic names and would silently defeat every opt-out.
      final topicIntent = await _loadTopicIntentOrShowAll();
      final items = await _service.fetchInbox(
        userId: userId,
        locale: _locale,
        campusId: _campusId,
        topicIntent: topicIntent,
      );
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Reload without showing the full-screen loading state.
  Future<void> refresh() async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return;

    try {
      final topicIntent = await _loadTopicIntentOrShowAll();
      final items = await _service.fetchInbox(
        userId: userId,
        locale: _locale,
        campusId: _campusId,
        topicIntent: topicIntent,
      );
      state = state.copyWith(items: items, clearError: true);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> markRead(AppNotification notification) async {
    final userId = _userId;
    if (userId == null || userId.isEmpty || notification.read) return;

    // Optimistically update local state for instant UI feedback.
    state = state.copyWith(
      items: [
        for (final item in state.items)
          item.id == notification.id ? item.copyWith(read: true) : item,
      ],
    );

    try {
      await _service.markAsRead(notification, userId: userId);
      // Refresh so we pick up the persisted user_notifications row id.
      await refresh();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  @override
  void dispose() {
    _subscription?.close();
    _foregroundSubscription?.cancel();
    super.dispose();
  }
}

/// Inbox state provider. Rebuilds when the signed-in user, their home campus,
/// or the locale changes — a campus change must rebuild this, or a student
/// who transfers keeps seeing their old campus's announcements alongside the
/// new one (see [isTopicAudienceVisible]).
final notificationInboxProvider =
    StateNotifierProvider<NotificationInboxNotifier, NotificationInboxState>((
      ref,
    ) {
      final service = ref.watch(notificationInboxServiceProvider);
      final userId = ref.watch(authStateProvider).user?.id;
      final locale = ref.watch(localeProvider).languageCode;
      final notificationService = ref.watch(notificationServiceProvider);
      final campusId = ref.watch(
        authStateProvider.select((state) => state.user?.campusId),
      );

      return NotificationInboxNotifier(
        service,
        notificationService: notificationService,
        userId: userId,
        locale: locale,
        campusId: campusId,
      );
    });

/// Convenience provider for the unread badge count.
final unreadCountProvider = Provider<int>((ref) {
  return ref.watch(notificationInboxProvider).unreadCount;
});

/// Fetches a single announcement by id, localized and merged with the current
/// user's read state. Keyed by announcement id. Used by the announcement
/// detail screen.
final announcementDetailProvider =
    FutureProvider.family<AppNotification?, String>((ref, announcementId) async {
      final service = ref.watch(notificationInboxServiceProvider);
      final userId = ref.watch(authStateProvider).user?.id;
      final locale = ref.watch(localeProvider).languageCode;

      return service.fetchAnnouncementById(
        announcementId: announcementId,
        locale: locale,
        userId: userId,
      );
    });

/// Keeps this device's Appwrite subscriptions in step with the signed-in
/// student and their home campus.
///
/// This is what makes `reconcile()` run at all for a returning student: the
/// prompt only fires once, and the settings screen only fires when a switch is
/// touched. Watching the campus as well means a student who transfers stops
/// receiving their old campus's notifications, which nothing else would
/// trigger.
///
/// Reconciliation is idempotent, so re-running it on every auth or campus
/// change is free when nothing has actually changed.
final topicReconcileProvider = FutureProvider<void>((ref) async {
  final (ready, campusId) = ref.watch(
    authStateProvider.select(
      (state) => (
        !state.isLoading && state.isAuthenticated,
        state.user?.campusId,
      ),
    ),
  );
  if (!ready) return;
  await ref
      .read(notificationServiceProvider)
      .reconcile(campusId: campusId);
});
