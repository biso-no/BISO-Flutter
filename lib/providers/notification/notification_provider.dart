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
      final topicSubscriptions =
          await _notificationService.ensureTopicSubscriptionsLoaded();
      
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
/// subscriptions to match. A failed reconcile reverts the optimistic update
/// and reports failure to the caller, rather than surfacing an error state
/// that would hide every switch (see [setTopic]).
class TopicIntentNotifier extends StateNotifier<AsyncValue<Map<String, bool>>> {
  TopicIntentNotifier(this._service, this._campusId)
    : super(const AsyncValue.loading()) {
    _load();
  }

  final NotificationService _service;
  final String? _campusId;

  Future<void> _load() async {
    try {
      final intent = await _service.loadTopicIntent();
      if (mounted) state = AsyncValue.data(intent);
    } catch (error, stackTrace) {
      debugPrint('TopicIntentNotifier load failed: $error');
      if (mounted) state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Returns true when the change was saved and this device reconciled.
  ///
  /// A failure reverts the switch and returns false; the caller tells the
  /// student. The state stays `AsyncValue.data` throughout — deliberately.
  /// Riverpod flushes at most one notification per event-loop turn, so
  /// assigning `data(current)` and then `error(...)` would render only the
  /// error: the revert would never be seen, and the whole card would be
  /// replaced by an error message that hides all four switches. Since this
  /// provider is not autoDispose, nothing short of an app restart would bring
  /// them back.
  Future<bool> setTopic(String topicId, bool enabled) async {
    final current = state.value;
    if (current == null) return false;

    final updated = <String, bool>{...current, topicId: enabled};
    // Optimistic, so the switch responds immediately.
    state = AsyncValue.data(updated);
    try {
      await _service.saveTopicIntent(updated);
      await _service.reconcile(campusId: _campusId);
      return true;
    } catch (error) {
      debugPrint('TopicIntentNotifier.setTopic($topicId) failed: $error');
      // The sole terminal state, so the revert is what the student actually
      // sees: the switch goes back and the card stays usable.
      if (mounted) state = AsyncValue.data(current);
      return false;
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

  RealtimeSubscription? _subscription;
  StreamSubscription<void>? _foregroundSubscription;

  NotificationInboxNotifier(
    this._service, {
    required NotificationService notificationService,
    required String? userId,
    required String locale,
  }) : _notificationService = notificationService,
       _userId = userId,
       _locale = locale,
       super(const NotificationInboxState()) {
    if (_userId != null && _userId.isNotEmpty) {
      load();
      _subscription = _service.subscribe(onChange: refresh);
      _foregroundSubscription = _notificationService.onForegroundMessage.listen(
        (_) => refresh(),
      );
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
      final subscriptions =
          await _notificationService.ensureTopicSubscriptionsLoaded();
      final items = await _service.fetchInbox(
        userId: userId,
        locale: _locale,
        topicSubscriptions: subscriptions,
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
      final subscriptions =
          await _notificationService.ensureTopicSubscriptionsLoaded();
      final items = await _service.fetchInbox(
        userId: userId,
        locale: _locale,
        topicSubscriptions: subscriptions,
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

/// Inbox state provider. Rebuilds when the signed-in user or locale changes.
final notificationInboxProvider =
    StateNotifierProvider<NotificationInboxNotifier, NotificationInboxState>((
      ref,
    ) {
      final service = ref.watch(notificationInboxServiceProvider);
      final userId = ref.watch(authStateProvider).user?.id;
      final locale = ref.watch(localeProvider).languageCode;
      final notificationService = ref.watch(notificationServiceProvider);

      return NotificationInboxNotifier(
        service,
        notificationService: notificationService,
        userId: userId,
        locale: locale,
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
