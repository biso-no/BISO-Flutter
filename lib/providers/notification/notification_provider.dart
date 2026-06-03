import 'dart:async';

import 'package:appwrite/appwrite.dart';
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
      
      // Load topic subscriptions
      final topicSubscriptions = _notificationService.topicSubscriptions;
      
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
  final String? _userId;
  final String _locale;

  RealtimeSubscription? _subscription;
  StreamSubscription<void>? _foregroundSubscription;

  NotificationInboxNotifier(
    this._service, {
    required String? userId,
    required String locale,
    required Stream<void> onForegroundMessage,
  }) : _userId = userId,
       _locale = locale,
       super(const NotificationInboxState()) {
    if (_userId != null && _userId.isNotEmpty) {
      load();
      _subscription = _service.subscribe(onChange: refresh);
      _foregroundSubscription = onForegroundMessage.listen((_) => refresh());
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
      final items = await _service.fetchInbox(userId: userId, locale: _locale);
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
      final items = await _service.fetchInbox(userId: userId, locale: _locale);
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
        userId: userId,
        locale: locale,
        onForegroundMessage: notificationService.onForegroundMessage,
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
