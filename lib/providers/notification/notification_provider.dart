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
  TopicIntentNotifier(
    this._service,
    this._campusId, {
    required String? studentId,
    required String? Function() signedInStudentId,
  }) : _studentId = studentId,
       _signedInStudentId = signedInStudentId,
       super(const AsyncValue.loading()) {
    _load();
  }

  final NotificationService _service;
  final String? _campusId;

  /// The student this notifier was built for, and so the student every save
  /// it queues belongs to: [topicIntentProvider] builds a new notifier when
  /// the signed-in student changes.
  final String? _studentId;

  /// Who is signed in now, asked afresh on every call - even once this
  /// notifier has been disposed.
  final String? Function() _signedInStudentId;

  /// Whether the student this notifier's saves belong to is still the one
  /// signed in (see [_commit]).
  bool get _studentStillSignedIn =>
      _studentId != null && _signedInStudentId() == _studentId;

  /// The student's intent as last confirmed persisted: what the server holds,
  /// as far as this notifier knows.
  ///
  /// Set by a successful load, and updated only once a save has succeeded —
  /// never by a tap. Every save's payload is this map plus that save's one
  /// change, and a failed save reverts its switch to this map's value. The
  /// switches themselves ([state]) are this map with every unresolved tap in
  /// [_queuedTaps] laid over it.
  ///
  /// Building payloads from the switches instead is what leaked a tap still
  /// queued behind a save into that save: it reached the server, then its own
  /// save failed and reverted the switch, which then showed a value the
  /// server did not hold.
  Map<String, bool>? _confirmed;

  /// The latest tap for each topic whose commit has not resolved yet.
  ///
  /// A commit that fails reverts its topic's switch only while it is still
  /// that topic's latest tap. If the student has tapped the same topic again
  /// since, the switch shows that newer tap, and the newer tap's commit —
  /// still queued — settles it.
  final Map<String, ({int sequence, bool enabled})> _queuedTaps = {};

  /// Numbers taps, so a commit can tell whether it is still its topic's
  /// latest.
  int _tapCount = 0;

  /// Serialises the network side of [setTopic], and [refresh].
  ///
  /// Two quick taps each call `setTopic`, and without this, both calls'
  /// `saveTopicIntent` requests fire at once — whichever one's response
  /// arrives *last* wins on the server, even if it is the older, staler one,
  /// silently resurrecting a setting the student just turned off. Chaining
  /// each save onto this tail forces them to run one at a time, in the order
  /// [setTopic] was called. A reload waits its turn the same way: its read
  /// could otherwise answer after a save had landed, and hand [_confirmed]
  /// the intent from before it.
  ///
  /// Every link swallows its own outcome (`.then((_) {}, onError: (_) {})`)
  /// before being stored back here, so one call's failure can never leave
  /// this future permanently rejected and wedge every *later* call's save
  /// from ever running.
  Future<void> _pendingSave = Future<void>.value();

  Future<void> _load() async {
    try {
      final intent = await _service.loadTopicIntent();
      _confirmed = intent;
      // Taps whose commits have not resolved stay on screen: each one's
      // commit settles its own switch, and nothing else would put back a tap
      // that this reload had hidden.
      if (mounted) {
        state = AsyncValue.data(<String, bool>{
          ...intent,
          for (final tap in _queuedTaps.entries) tap.key: tap.value.enabled,
        });
      }
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
  /// save is queued (see [_pendingSave]); [_commit] builds its payload once
  /// it is this call's turn to run.
  Future<ReconcileOutcome?> setTopic(String topicId, bool enabled) {
    final shown = state.value;
    if (shown == null || _confirmed == null) {
      return Future<ReconcileOutcome?>.value();
    }
    final sequence = ++_tapCount;
    _queuedTaps[topicId] = (sequence: sequence, enabled: enabled);

    // Optimistic, so the switch responds immediately.
    state = AsyncValue.data(<String, bool>{...shown, topicId: enabled});

    final result = _pendingSave.then(
      (_) => _commit(topicId, enabled, sequence),
    );
    _pendingSave = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Runs one tap's save, then reconciles. Always executes strictly after
  /// every previously queued commit and reload has finished, via
  /// [_pendingSave].
  ///
  /// The payload is [_confirmed] as it stands when this runs, plus this tap's
  /// one change: it holds every earlier save that succeeded, none that
  /// failed, and no tap still queued behind this one.
  ///
  /// A save belongs to the student who made it, and is written only while they
  /// are still the one signed in: checked before the save starts, and again
  /// once the account's preferences have been read, immediately before they
  /// are written back (see [NotificationService.saveTopicIntent]). A commit
  /// still queued when its student signs out and another signs in would
  /// otherwise save through the new session - the first student's choices,
  /// and the answered marker, in the second student's preferences, so the
  /// second student was never asked. Such a save is dropped: nothing is
  /// written to the preferences or to [state], nothing reconciles, and the
  /// result is null, since nothing was saved.
  ///
  /// [topicIntentProvider] also rebuilds this notifier when the campus
  /// changes, so a commit can find it disposed by the time its save completes.
  /// For the same student the save still counts — intent is campus-free, and
  /// genuinely the student's choice — but nothing else happens here: no state
  /// is read or written (StateNotifier asserts on both after dispose), and
  /// nothing reconciles a campus that is no longer the student's. The rebuilt
  /// notifier and the launch reconciler own the new campus. The result is then
  /// [ReconcileOutcome.unavailable]: saved, but this device was not updated by
  /// this call.
  Future<ReconcileOutcome?> _commit(
    String topicId,
    bool enabled,
    int sequence,
  ) async {
    final confirmed = _confirmed;
    if (confirmed == null) return null;
    if (!_studentStillSignedIn) return _dropSave(topicId, sequence);

    final bool saved;
    try {
      saved = await _service.saveTopicIntent(
        <String, bool>{...confirmed, topicId: enabled},
        onlyIf: () => _studentStillSignedIn,
      );
    } catch (error) {
      debugPrint(
        'TopicIntentNotifier.setTopic($topicId) failed to save: $error',
      );
      // Back to what the server holds — unless the student has tapped this
      // topic again since, in which case the switch shows that newer tap and
      // its own commit, still queued, settles it.
      final isLatestTap = _resolveTap(topicId, sequence);
      if (isLatestTap && mounted) {
        final shown = state.value;
        if (shown != null) {
          state = AsyncValue.data(<String, bool>{
            ...shown,
            topicId: (_confirmed ?? confirmed)[topicId] ?? false,
          });
        }
      }
      return null;
    }
    if (!saved) return _dropSave(topicId, sequence);

    // Intent is saved from here on. Whatever reconcile() does or doesn't
    // manage on this device, the switch must not revert — the student's
    // choice is real, saved, and will be applied the next time reconcile
    // runs, so reverting it here would be a lie.
    //
    // Nor is anything written back to the switches: they already show this
    // value, or a newer tap of the same topic that is still queued. Writing
    // this value back would flick that newer tap off until its own commit ran.
    _confirmed = <String, bool>{...(_confirmed ?? confirmed), topicId: enabled};
    _resolveTap(topicId, sequence);

    if (!mounted || !_studentStillSignedIn) return ReconcileOutcome.unavailable;

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

  /// Gives up a save whose student is no longer the one signed in: nothing is
  /// written to the preferences or to [state], and nothing reconciles. Null,
  /// because nothing was saved.
  ReconcileOutcome? _dropSave(String topicId, int sequence) {
    debugPrint(
      'TopicIntentNotifier.setTopic($topicId): not saved, because the student '
      'who made the change is no longer signed in',
    );
    _resolveTap(topicId, sequence);
    return null;
  }

  /// Forgets [topicId]'s queued tap if [sequence] is still its latest, and
  /// reports whether it was.
  bool _resolveTap(String topicId, int sequence) {
    if (_queuedTaps[topicId]?.sequence != sequence) return false;
    _queuedTaps.remove(topicId);
    return true;
  }

  /// Reloads the intent from the server, once every save already queued has
  /// resolved (see [_pendingSave]).
  Future<void> refresh() {
    final run = _pendingSave.then((_) => _load());
    _pendingSave = run.then((_) {}, onError: (_) {});
    return run;
  }
}

/// Rebuilds when the signed-in student or their home campus changes: a campus
/// move resubscribes this device, and a notifier, with every save it has
/// queued, belongs to one student (see [TopicIntentNotifier._commit]).
final topicIntentProvider =
    StateNotifierProvider<TopicIntentNotifier, AsyncValue<Map<String, bool>>>((
      ref,
    ) {
      final service = ref.watch(notificationServiceProvider);
      final (studentId, campusId) = ref.watch(
        authStateProvider.select(
          (state) => (state.signedInUserId, state.user?.campusId),
        ),
      );
      // Asked through the container, not this ref: a save asks after the
      // student has changed, when a ref whose dependency changed may not be
      // used.
      final container = ref.container;
      return TopicIntentNotifier(
        service,
        campusId,
        studentId: studentId,
        signedInStudentId: () =>
            container.read(authStateProvider).signedInUserId,
      );
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
