import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart'
    as permission_handler;
import 'package:appwrite/appwrite.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/notification_topics.dart';
import 'appwrite_service.dart';
import 'deep_link_service.dart';
import 'device_subscription_store.dart';
import 'topic_reconciler.dart';

/// Reads the stored topic flags out of an Appwrite prefs value.
///
/// Returns `null` when nothing is stored, which is the caller's signal to apply
/// the defaults. Appwrite serialises preferences as JSON from a PHP backend,
/// where an empty map round-trips as `[]` rather than `{}` — so an account that
/// has never saved these prefs reads back a `List`, and a plain cast to `Map`
/// throws. An empty value carries no preferences either way, so it is reported
/// the same as an absent one.
///
/// Extracted as a top-level, `@visibleForTesting` function (rather than kept
/// inline in the service) because [NotificationService] is a singleton over a
/// global Appwrite `Account`, and the decoding is the part worth testing.
@visibleForTesting
Map<String, bool>? decodeTopicSubscriptions(Object? value) {
  if (value is! Map || value.isEmpty) return null;
  return <String, bool>{
    for (final entry in value.entries)
      if (entry.value is bool) entry.key.toString(): entry.value as bool,
  };
}

/// Reads the stored `topicId -> Appwrite subscriber $id` map out of a prefs
/// value, tolerating the same empty-list shape described on
/// [decodeTopicSubscriptions].
@visibleForTesting
Map<String, String> decodeTopicSubscriberIds(Object? value) {
  if (value is! Map) return const <String, String>{};
  return <String, String>{
    for (final entry in value.entries)
      if (entry.value is String) entry.key.toString(): entry.value as String,
  };
}

/// The Appwrite Messaging provider `$id` for FCM push.
///
/// Not `'fcm'`. The project has no provider by that name, and passing it is why
/// push targets were never created.
const String kFcmProviderId = 'push';

/// Per-user intent: which logical topics this student wants. Campus-free.
const String kTopicIntentPrefKey = 'notification_topics';

/// Marks the first-run prompt as answered. Its absence is what triggers it.
const String kTopicIntentSetAtPrefKey = 'notification_topics_set_at';

/// The pre-migration key, still read once to carry old choices forward.
const String kLegacyTopicSubscriptionsPrefKey = 'topic_subscriptions';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal() : _account = account;

  /// Builds a throwaway instance against a caller-supplied [Account], so the
  /// preference-loading paths can be driven without a network or a signed-in
  /// user. Production code goes through the [NotificationService] singleton.
  @visibleForTesting
  NotificationService.withAccount(this._account);

  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;
  final Account _account;
  final DeviceSubscriptionStore _store = DeviceSubscriptionStore();
  static final Messaging _messaging = messaging;

  String? _fcmToken;
  String? _pushTargetId;
  bool _isInitialized = false;
  final Map<String, bool> _topicSubscriptions = {};

  /// The campus most recently passed to [reconcile].
  ///
  /// Cached so a token refresh — which Firebase fires on its own schedule,
  /// decoupled from any UI event that would otherwise carry the campus along
  /// — can re-run [reconcile] without a caller supplying it again.
  String? _lastCampusId;

  /// Maps a topicId to the Appwrite subscriber `$id` returned by
  /// [Messaging.createSubscriber]. Needed to delete the subscriber on
  /// unsubscribe. Persisted to user preferences alongside the bool map.
  final Map<String, String> _topicSubscriberIds = {};

  /// Broadcasts every foreground [RemoteMessage] so providers (e.g. the inbox)
  /// can refresh in response to a push that arrives while the app is open.
  final StreamController<RemoteMessage> _foregroundMessageController =
      StreamController<RemoteMessage>.broadcast();

  /// Stream of foreground push messages.
  Stream<RemoteMessage> get onForegroundMessage =>
      _foregroundMessageController.stream;

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Configure Firebase Messaging
      await _configureFirebaseMessaging();

      // Get FCM token
      await _getFCMToken();

      _isInitialized = true;
      debugPrint('NotificationService initialized successfully');
    } catch (e) {
      debugPrint('Failed to initialize NotificationService: $e');
    }
  }

  /// Configure Firebase Messaging settings
  Future<void> _configureFirebaseMessaging() async {
    // Set foreground notification presentation options
    await _firebaseMessaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Listen to foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Listen to when user taps notification to open app
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Handle notification when app is launched from terminated state
    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
  }

  /// Get FCM token for this device
  Future<String?> _getFCMToken() async {
    try {
      _fcmToken = await _firebaseMessaging.getToken();
      debugPrint('FCM Token: $_fcmToken');

      // Listen for token refresh
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        unawaited(_reconcileAfterTokenRefresh());
      });

      return _fcmToken;
    } catch (e) {
      debugPrint('Failed to get FCM token: $e');
      return null;
    }
  }

  /// Re-run [reconcile] after a token refresh.
  ///
  /// `resolvePushTarget` alone is not enough here: when the previously stored
  /// target 404s, the create path runs and `_adoptTarget` deliberately clears
  /// this device's subscriber map (a subscriber belongs to the old target, not
  /// the new one — see its doc comment), which would otherwise leave the
  /// device silently unsubscribed from everything until the next cold start.
  /// `reconcile` resolves the target *and* recreates whatever subscriptions
  /// the clear wiped out.
  ///
  /// `onTokenRefresh` gives its listener no way to be awaited by a caller, so
  /// a throw here must be caught rather than left to become an unhandled
  /// async error.
  Future<void> _reconcileAfterTokenRefresh() async {
    try {
      await reconcile(campusId: _lastCampusId);
    } catch (e) {
      debugPrint('onTokenRefresh: reconcile failed: $e');
    }
  }

  /// Request notification permissions from the user
  Future<bool> requestPermission() async {
    try {
      // First check system permission
      final systemPermission = await permission_handler.Permission.notification
          .request();
      if (systemPermission != permission_handler.PermissionStatus.granted) {
        debugPrint('System notification permission denied');
        return false;
      }

      // Then request Firebase messaging permission
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      final isGranted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      debugPrint(
        'Firebase notification permission: ${settings.authorizationStatus}',
      );

      if (isGranted && _fcmToken != null) {
        await resolvePushTarget(_fcmToken!);
        await _loadTopicSubscriptions();
      }

      return isGranted;
    } catch (e) {
      debugPrint('Failed to request notification permission: $e');
      return false;
    }
  }

  /// Check if notifications are currently enabled
  Future<bool> areNotificationsEnabled() async {
    try {
      final settings = await _firebaseMessaging.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('Failed to check notification status: $e');
      return false;
    }
  }

  /// Establish this device's Appwrite push target for [token] and return its id.
  ///
  /// Ordered so the common case is a single call. The 409 branch is the one
  /// that matters: Appwrite rejects a second target for an identifier it
  /// already holds, which happens on every launch after the first. The old code
  /// swallowed that and left `_pushTargetId` null, so every later
  /// `subscribeToTopic` returned early and topic subscription could never work.
  Future<String?> resolvePushTarget(String token) async {
    final storedId = await _store.readTargetId();
    if (storedId != null) {
      try {
        final target = await _account.updatePushTarget(
          targetId: storedId,
          identifier: token,
        );
        _pushTargetId = target.$id;
        return target.$id;
      } on AppwriteException catch (e) {
        // The target was deleted server-side, or the id is stale. Fall through
        // and create a fresh one.
        debugPrint(
          'resolvePushTarget: update of $storedId failed '
          '(${e.code}) ${e.message}; creating a new target',
        );
      }
    }

    try {
      final target = await _account.createPushTarget(
        targetId: ID.unique(),
        identifier: token,
        providerId: kFcmProviderId,
      );
      await _adoptTarget(target.$id, storedId);
      return target.$id;
    } on AppwriteException catch (e) {
      if (e.code != 409) {
        debugPrint(
          'resolvePushTarget: create failed (${e.code}) ${e.message}',
        );
        return null;
      }
    }

    // 409: a target already holds this token. Find and adopt it.
    try {
      final user = await _account.get();
      for (final target in user.targets) {
        if (target.identifier == token) {
          await _adoptTarget(target.$id, storedId);
          return target.$id;
        }
      }
      debugPrint(
        'resolvePushTarget: got 409 but no target matches this token; '
        'push is unavailable on this device',
      );
    } on AppwriteException catch (e) {
      debugPrint(
        'resolvePushTarget: could not read targets after 409 '
        '(${e.code}) ${e.message}',
      );
    }
    return null;
  }

  /// Record [targetId] as this device's target, forgetting the stored
  /// subscriber ids if it replaces a different one.
  ///
  /// A subscriber belongs to a *target*. When the target changes identity the
  /// old subscribers are attached to something that no longer exists — but the
  /// stored map would still claim those topics are covered, so the next
  /// reconcile would compute an empty diff and the device would go silently
  /// unsubscribed. Clearing forces them to be recreated against the new target.
  Future<void> _adoptTarget(String targetId, String? previousId) async {
    if (previousId != null && previousId != targetId) {
      await _store.writeSubscriberIds(const <String, String>{});
    }
    await _store.writeTargetId(targetId);
    _pushTargetId = targetId;
  }

  /// The student's topic intent, migrating a pre-existing legacy map if that is
  /// all the account has.
  Future<Map<String, bool>> loadTopicIntent() async {
    try {
      final prefs = await _account.getPrefs();
      final stored = decodeTopicSubscriptions(prefs.data[kTopicIntentPrefKey]);
      if (stored != null) {
        return <String, bool>{...kDefaultTopicIntent, ...stored}
          ..removeWhere((key, _) => !kDefaultTopicIntent.containsKey(key));
      }
      return migrateLegacyIntent(
        decodeTopicSubscriptions(prefs.data[kLegacyTopicSubscriptionsPrefKey]),
      );
    } catch (e) {
      debugPrint('loadTopicIntent failed: $e');
      return Map<String, bool>.from(kDefaultTopicIntent);
    }
  }

  /// Persist intent and mark the prompt answered.
  ///
  /// Written before the OS permission request and regardless of its outcome: a
  /// student who declines the system dialog has still expressed a preference,
  /// and it takes effect if they enable notifications later.
  Future<void> saveTopicIntent(Map<String, bool> intent) async {
    final prefs = await _account.getPrefs();
    final updated = Map<String, dynamic>.from(prefs.data);
    updated[kTopicIntentPrefKey] = intent;
    updated[kTopicIntentSetAtPrefKey] = DateTime.now().toIso8601String();
    await _account.updatePrefs(prefs: updated);
  }

  /// Whether this student has already been asked to pick topics.
  ///
  /// A legacy `topic_subscriptions` map cannot count as an answer: until this
  /// was fixed, `_loadTopicSubscriptions()` wrote that key automatically, for
  /// every signed-in student, on essentially every launch — never because
  /// anyone chose anything. Its mere presence therefore cannot distinguish a
  /// student who really answered from one who was never asked, so only
  /// [kTopicIntentSetAtPrefKey] — written exclusively by [saveTopicIntent],
  /// which only runs from the prompt's Continue button — counts.
  Future<bool> hasAnsweredTopicPrompt() async {
    try {
      final prefs = await _account.getPrefs();
      return prefs.data[kTopicIntentSetAtPrefKey] != null;
    } catch (e) {
      debugPrint('hasAnsweredTopicPrompt failed: $e');
      // Fail closed: do not interrupt a student because a read failed.
      return true;
    }
  }

  /// Bring this device's Appwrite subscriptions in line with the student's
  /// intent for [campusId].
  ///
  /// Idempotent by construction — it diffs desired against observed rather than
  /// replaying toggles — so it is safe to call on every launch, and two devices
  /// on one account reconcile independently without coordinating.
  Future<void> reconcile({required String? campusId}) async {
    // Cached before any early return, so a later token refresh — which has no
    // campusId of its own to pass in — can still reconcile against the most
    // recent one this method was actually asked to use.
    _lastCampusId = campusId;

    if (!await areNotificationsEnabled()) {
      debugPrint('reconcile: notifications not permitted; intent kept for later');
      return;
    }

    final token = _fcmToken ?? await _firebaseMessaging.getToken();
    if (token == null) {
      debugPrint('reconcile: no FCM token; skipping');
      return;
    }
    _fcmToken = token;

    final targetId = await resolvePushTarget(token);
    if (targetId == null) {
      debugPrint('reconcile: no push target; skipping subscription changes');
      return;
    }

    final intent = await loadTopicIntent();
    final desired = appwriteTopicIdsFor(intent: intent, campusId: campusId);
    final current = await _store.readSubscriberIds();
    final diff = computeTopicDiff(desired: desired, current: current);
    if (diff.isEmpty) return;

    final updated = Map<String, String>.from(current);

    for (final topicId in diff.toCreate) {
      try {
        final subscriber = await _messaging.createSubscriber(
          topicId: topicId,
          subscriberId: ID.unique(),
          targetId: targetId,
        );
        updated[topicId] = subscriber.$id;
      } on AppwriteException catch (e) {
        // Best-effort per topic: one failure must not abort the rest. The next
        // reconcile retries, because the diff recomputes from observed state.
        debugPrint('reconcile: subscribe to $topicId failed (${e.code}) ${e.message}');
      }
    }

    for (final topicId in diff.toDelete) {
      final subscriberId = updated[topicId];
      if (subscriberId == null) continue;
      try {
        await _messaging.deleteSubscriber(
          topicId: topicId,
          subscriberId: subscriberId,
        );
        updated.remove(topicId);
      } on AppwriteException catch (e) {
        if (e.code == 404) {
          // Already gone server-side; stop tracking it.
          updated.remove(topicId);
          continue;
        }
        debugPrint('reconcile: unsubscribe from $topicId failed (${e.code}) ${e.message}');
      }
    }

    await _store.writeSubscriberIds(updated);
  }

  /// Update chat notification preference in Appwrite
  Future<void> updateChatNotificationPreference(bool enabled) async {
    try {
      // Get current user preferences
      final prefs = await _account.getPrefs();

      // Update chat notification preference
      final updatedPrefs = Map<String, dynamic>.from(prefs.data);
      updatedPrefs['chat_notifications'] = enabled;
      updatedPrefs['chat_notifications_updated_at'] = DateTime.now()
          .toIso8601String();

      // Save updated preferences
      await _account.updatePrefs(prefs: updatedPrefs);
      debugPrint('Chat notification preference updated: $enabled');
    } catch (e) {
      debugPrint('Failed to update chat notification preference: $e');
      rethrow;
    }
  }

  /// Get chat notification preference from Appwrite
  Future<bool> getChatNotificationPreference() async {
    try {
      final prefs = await _account.getPrefs();
      // Default to true if not set (opt-in for notifications)
      return prefs.data['chat_notifications'] ?? true;
    } catch (e) {
      debugPrint('Failed to get chat notification preference: $e');
      return true; // Default to enabled
    }
  }

  /// Get FCM token for current user
  String? get fcmToken => _fcmToken;

  /// Get push target ID
  String? get pushTargetId => _pushTargetId;

  /// Subscribe to a topic
  Future<void> subscribeToTopic(String topicId) async {
    try {
      if (_pushTargetId == null) {
        debugPrint('No push target available for topic subscription');
        return;
      }

      final subscriber = await _messaging.createSubscriber(
        topicId: topicId,
        subscriberId: ID.unique(),
        targetId: _pushTargetId!,
      );

      _topicSubscriptions[topicId] = true;
      _topicSubscriberIds[topicId] = subscriber.$id;
      await _saveTopicSubscriptions();
      debugPrint('Subscribed to topic: $topicId (${subscriber.$id})');
    } catch (e) {
      debugPrint('Failed to subscribe to topic $topicId: $e');
      rethrow;
    }
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topicId) async {
    try {
      // Delete the Appwrite subscriber if we have its id, so the device
      // actually stops receiving messages for this topic.
      final subscriberId = _topicSubscriberIds[topicId];
      if (subscriberId != null && subscriberId.isNotEmpty) {
        try {
          await _messaging.deleteSubscriber(
            topicId: topicId,
            subscriberId: subscriberId,
          );
          debugPrint('Deleted subscriber $subscriberId for topic: $topicId');
        } catch (e) {
          debugPrint('Failed to delete subscriber for topic $topicId: $e');
        }
        _topicSubscriberIds.remove(topicId);
      }

      _topicSubscriptions[topicId] = false;
      await _saveTopicSubscriptions();
      debugPrint('Unsubscribed from topic: $topicId');
    } catch (e) {
      debugPrint('Failed to unsubscribe from topic $topicId: $e');
      rethrow;
    }
  }

  /// Get topic subscription status
  bool isSubscribedToTopic(String topicId) {
    return _topicSubscriptions[topicId] ?? false;
  }

  /// Get all topic subscriptions
  Map<String, bool> get topicSubscriptions => Map.from(_topicSubscriptions);

  bool _topicSubscriptionsLoaded = false;

  /// Ensure the saved topic opt-outs are loaded from user preferences before a
  /// consumer (e.g. the inbox) reads [topicSubscriptions]. `_loadTopicSubscriptions`
  /// otherwise only runs after a notification-permission request, so on a fresh
  /// start the in-memory map would be empty and opt-outs ignored.
  Future<Map<String, bool>> ensureTopicSubscriptionsLoaded() async {
    if (!_topicSubscriptionsLoaded) {
      await _loadTopicSubscriptions();
    }
    return topicSubscriptions;
  }

  /// Load topic subscriptions from user preferences
  Future<void> _loadTopicSubscriptions() async {
    try {
      final prefs = await _account.getPrefs();
      final subscriptions = decodeTopicSubscriptions(
        prefs.data['topic_subscriptions'],
      );

      _topicSubscriberIds
        ..clear()
        ..addAll(decodeTopicSubscriberIds(prefs.data['topic_subscriber_ids']));

      if (subscriptions != null) {
        _topicSubscriptions
          ..clear()
          ..addAll(subscriptions);
      } else {
        // In-memory defaults only. The legacy `topic_subscriptions` key is
        // read-only from here on — this used to call `_saveTopicSubscriptions()`,
        // which fabricated a "chosen" map for a student who had never chosen
        // anything, and that machine-written map was indistinguishable from a
        // real answer to `hasAnsweredTopicPrompt()`. A genuine legacy map is
        // instead migrated, once, by `loadTopicIntent()`.
        _topicSubscriptions.addAll({
          'events': true,
          'products': true,
          'jobs': true,
          'expenses': false,
        });
      }

      // Marked only once the read actually succeeded. Setting this up front
      // would turn a transient failure — no network at launch, say — into a
      // permanent one: the opt-outs would stay unloaded for the rest of the
      // session with no further attempt to fetch them.
      _topicSubscriptionsLoaded = true;
      debugPrint('Loaded topic subscriptions: $_topicSubscriptions');
    } catch (e) {
      debugPrint('Failed to load topic subscriptions: $e');
    }
  }

  /// Save topic subscriptions to user preferences
  Future<void> _saveTopicSubscriptions() async {
    try {
      final prefs = await _account.getPrefs();
      final updatedPrefs = Map<String, dynamic>.from(prefs.data);
      updatedPrefs['topic_subscriptions'] = _topicSubscriptions;
      updatedPrefs['topic_subscriber_ids'] = _topicSubscriberIds;
      updatedPrefs['topic_subscriptions_updated_at'] = DateTime.now().toIso8601String();

      await _account.updatePrefs(prefs: updatedPrefs);
      debugPrint('Topic subscriptions saved');
    } catch (e) {
      debugPrint('Failed to save topic subscriptions: $e');
    }
  }

  /// Update notification preference for a specific topic
  Future<void> updateTopicSubscription(String topicId, bool enabled) async {
    try {
      if (enabled) {
        await subscribeToTopic(topicId);
      } else {
        await unsubscribeFromTopic(topicId);
      }
    } catch (e) {
      debugPrint('Failed to update topic subscription for $topicId: $e');
      rethrow;
    }
  }

  /// Handle foreground messages
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('Received foreground message: ${message.messageId}');
    debugPrint('Message data: ${message.data}');

    if (message.notification != null) {
      debugPrint('Message notification: ${message.notification!.title}');
      debugPrint('Message body: ${message.notification!.body}');
    }

    // Broadcast to listeners (e.g. the inbox provider) so they can refresh
    // while the app is open.
    if (!_foregroundMessageController.isClosed) {
      _foregroundMessageController.add(message);
    }
  }

  /// Handle notification tap
  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('Notification tapped: ${message.messageId}');
    debugPrint('Message data: ${message.data}');

    // Handle navigation based on message data
    final data = message.data;
    final type = data['type'] as String?;
    
    switch (type) {
      case 'chat':
        _handleChatNotification(data);
        break;
      case 'event':
        _handleEventNotification(data);
        break;
      case 'product':
        _handleProductNotification(data);
        break;
      case 'job':
        _handleJobNotification(data);
        break;
      case 'expense':
        _handleExpenseNotification(data);
        break;
      case 'announcement':
        _handleAnnouncementNotification(data);
        break;
      default:
        debugPrint('Unknown notification type: $type');
    }
  }

  /// Handle announcement notification tap.
  ///
  /// Prefers the server-provided `deep_link` (e.g. `biso://event?id=<id>` or
  /// `biso://announcement?id=<id>`). Falls back to event handling when an
  /// `event_id` is present, otherwise opens the notifications inbox.
  void _handleAnnouncementNotification(Map<String, dynamic> data) {
    final deepLinkService = DeepLinkService();

    final deepLink = data['deep_link'] as String?;
    if (deepLink != null && deepLink.isNotEmpty) {
      final uri = Uri.tryParse(deepLink);
      if (uri != null) {
        debugPrint('Navigating via announcement deep link: $deepLink');
        deepLinkService.handleDeepLink(uri);
        return;
      }
    }

    final eventId = data['event_id'] as String?;
    if (eventId != null && eventId.isNotEmpty) {
      debugPrint('Navigating to announcement event: $eventId');
      deepLinkService.handleDeepLink(Uri.parse('biso://event?id=$eventId'));
      return;
    }

    final announcementId = data['announcement_id'] as String?;
    if (announcementId != null && announcementId.isNotEmpty) {
      debugPrint('Navigating to announcement detail: $announcementId');
      deepLinkService.handleDeepLink(
        Uri.parse('biso://announcement?id=$announcementId'),
      );
      return;
    }

    debugPrint('Opening notifications inbox for announcement');
    final context = navigatorKey.currentContext;
    if (context != null) {
      context.go('/notifications');
    }
  }

  /// Handle chat notification tap
  void _handleChatNotification(Map<String, dynamic> data) {
    final chatId = data['chat_id'] as String?;
    if (chatId != null) {
      debugPrint('Navigating to chat: $chatId');
      final uri = Uri.parse('biso://chat?id=$chatId');
      final deepLinkService = DeepLinkService();
      deepLinkService.handleDeepLink(uri);
    }
  }

  /// Handle event notification tap
  void _handleEventNotification(Map<String, dynamic> data) {
    final eventId = data['event_id'] as String?;
    if (eventId != null) {
      debugPrint('Navigating to event: $eventId');
      final uri = Uri.parse('biso://event?id=$eventId');
      final deepLinkService = DeepLinkService();
      deepLinkService.handleDeepLink(uri);
    }
  }

  /// Handle product notification tap
  void _handleProductNotification(Map<String, dynamic> data) {
    final productId = data['product_id'] as String?;
    if (productId != null) {
      debugPrint('Navigating to product: $productId');
      final uri = Uri.parse('biso://product?id=$productId');
      final deepLinkService = DeepLinkService();
      deepLinkService.handleDeepLink(uri);
    }
  }

  /// Handle job notification tap
  void _handleJobNotification(Map<String, dynamic> data) {
    final jobId = data['job_id'] as String?;
    if (jobId != null) {
      debugPrint('Navigating to job: $jobId');
      final uri = Uri.parse('biso://job?id=$jobId');
      final deepLinkService = DeepLinkService();
      deepLinkService.handleDeepLink(uri);
    }
  }

  /// Handle expense notification tap
  void _handleExpenseNotification(Map<String, dynamic> data) {
    final expenseId = data['expense_id'] as String?;
    if (expenseId != null) {
      debugPrint('Navigating to expense: $expenseId');
      final uri = Uri.parse('biso://expense?id=$expenseId');
      final deepLinkService = DeepLinkService();
      deepLinkService.handleDeepLink(uri);
    }
  }

  /// Detach this device on logout.
  ///
  /// Order matters: the subscriber and target deletions need the session, so
  /// they must happen before it is destroyed. Without this the Appwrite-side
  /// subscriptions survive and the device keeps receiving pushes for an account
  /// that is no longer signed in.
  ///
  /// Intent is deliberately left in account preferences — it is per-user, and
  /// the next login reconciles from it.
  Future<void> clearToken() async {
    // Every await below is guarded — logout (see AuthNotifier.logout) treats
    // this whole method as best-effort, so a storage or network failure here
    // must never propagate and block the session from being deleted.
    Map<String, String> subscriberIds = const <String, String>{};
    try {
      subscriberIds = await _store.readSubscriberIds();
    } catch (e) {
      debugPrint('clearToken: could not read subscriber ids: $e');
    }
    for (final entry in subscriberIds.entries) {
      try {
        await _messaging.deleteSubscriber(
          topicId: entry.key,
          subscriberId: entry.value,
        );
      } on AppwriteException catch (e) {
        debugPrint('clearToken: could not remove ${entry.key} (${e.code}) ${e.message}');
      }
    }

    String? targetId;
    try {
      targetId = await _store.readTargetId();
    } catch (e) {
      debugPrint('clearToken: could not read target id: $e');
    }
    if (targetId != null) {
      try {
        await _account.deletePushTarget(targetId: targetId);
      } on AppwriteException catch (e) {
        debugPrint('clearToken: could not delete target (${e.code}) ${e.message}');
      }
    }

    try {
      await _store.clear();
    } catch (e) {
      debugPrint('clearToken: could not clear the local subscription store: $e');
    }
    _pushTargetId = null;
    _topicSubscriptions.clear();
    _topicSubscriberIds.clear();
    // Otherwise a sign-in by a different student later in the same session
    // would see `ensureTopicSubscriptionsLoaded()` short-circuit on this flag
    // and serve them whatever was left over in memory from the account that
    // just signed out.
    _topicSubscriptionsLoaded = false;

    try {
      await _firebaseMessaging.deleteToken();
      _fcmToken = null;
    } catch (e) {
      debugPrint('clearToken: could not delete the FCM token: $e');
    }
  }
}
