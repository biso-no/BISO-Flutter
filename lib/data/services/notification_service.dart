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

/// How long one run of [NotificationService]'s queue — a reconcile, a sign-out
/// cleanup, or a retried token invalidation — may hold the queue before it is
/// abandoned.
///
/// Runs are serialized, and nothing a run awaits has a timeout of its own, so
/// without this bound one request that never answers would stall every run
/// queued behind it until the app restarts — sign-out's cleanup included.
///
/// Deliberately generous. A healthy run is a handful of small requests: a
/// first reconcile makes about a dozen, a few seconds in all even on a mobile
/// connection, so this only cuts off a run that has stopped making progress.
/// Cutting off one that is still progressing has a cost: a subscribe already
/// on the wire can land after the bound, and a run past its bound may not
/// record the id (see `_QueueRun.ownsState`).
const Duration kNotificationRunTimeout = Duration(seconds: 30);

/// How long sign-out waits for [NotificationService.clearToken] before
/// deleting the session anyway.
///
/// Shorter than [kNotificationRunTimeout], because a student is watching a
/// spinner, and a normal cleanup is two or three requests. Cutting it short is
/// covered rather than silent: `clearToken` records the pending token
/// invalidation before anything that can be cut short, the cleanup carries on
/// in the background, and the invalidation is retried on the next launch if it
/// never succeeded.
const Duration kSignOutCleanupTimeout = Duration(seconds: 10);

/// What a `reconcile()` run actually achieved on this device.
///
/// `reconcile()` used to return `void` and swallow every failure — a missing
/// permission, a missing token, a missing push target, and every failed
/// subscribe/unsubscribe call all looked identical to a caller: nothing
/// thrown, nothing to see. That is precisely the shape of bug this branch
/// exists to fix: a student toggles a switch, believes they are subscribed,
/// and is not. This type makes each of those outcomes a distinct, reportable
/// value instead.
enum ReconcileOutcome {
  /// This device's subscriptions now match the student's intent (including
  /// the case where they already did, and there was nothing to change).
  applied,

  /// OS notification permission is not granted, so there is nothing to
  /// subscribe. Intent is saved and takes effect if they enable notifications.
  permissionDenied,

  /// Nothing could be attempted on this device: the permission status could
  /// not be read, or there is no FCM token, no push target, or no readable
  /// intent.
  unavailable,

  /// Some subscribe/unsubscribe calls failed; the device is partly reconciled.
  partiallyFailed,
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal()
    : _account = account,
      _messagingOverride = null,
      _store = DeviceSubscriptionStore();

  /// Builds a throwaway instance against a caller-supplied [Account] — and,
  /// optionally, [Messaging] and a [DeviceSubscriptionStore] — so the
  /// preference-loading, reconcile and sign-out paths can be driven without a
  /// network or a signed-in user. Production code goes through the
  /// [NotificationService] singleton.
  @visibleForTesting
  NotificationService.withAccount(
    this._account, {
    Messaging? messaging,
    DeviceSubscriptionStore? store,
  }) : _messagingOverride = messaging,
       _store = store ?? DeviceSubscriptionStore();

  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;
  final Account _account;
  final DeviceSubscriptionStore _store;

  /// The [Messaging] supplied to [NotificationService.withAccount], if any.
  final Messaging? _messagingOverride;

  /// Where subscribers are created and deleted: the app-wide Appwrite
  /// [Messaging] unless a test supplied its own. Resolved on use, as the static
  /// field this replaced was, so the singleton behaves exactly as before.
  Messaging get _messaging => _messagingOverride ?? messaging;

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

    // Queued, not awaited: startup must not wait on Firebase, and the queue
    // already keeps any reconcile from resolving a push target before this
    // has run. Retried at launch, not only from reconcile(), because the
    // launch reconciler does not run for a device nobody is signed in to —
    // which is exactly the device a failed sign-out left bound to an account.
    unawaited(retryPendingTokenInvalidation());
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

  /// Asks the OS, then Firebase, for notification permission, returning
  /// whether it ended up granted (including provisional on iOS).
  ///
  /// Extracted from [requestPermission] purely as a test seam. This
  /// project's tests are hand-written fakes over `Account` and
  /// [NotificationService] itself (see `NotificationService.withAccount`);
  /// there is no fake for the OS permission dialog or for Firebase's own
  /// `requestPermission` call, and this file's test suite otherwise never
  /// exercises `requestPermission` or `reconcile` directly for that reason.
  /// Overriding this one method lets a test drive [requestPermission]'s own
  /// logic — specifically, that a grant must subscribe this device (see the
  /// granted branch below) — without needing either of those.
  @visibleForTesting
  Future<bool> requestPlatformPermission() async {
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
    return isGranted;
  }

  /// Request notification permissions from the user.
  ///
  /// Returns whether permission is granted, and nothing else. Subscribing this
  /// device afterwards is best-effort: a failure there is logged, never
  /// reported as a denial. Callers act on `false` by telling the student to
  /// enable notifications in system settings and leaving chat notifications
  /// off (see `settings_screen_chat_tab.dart` and
  /// `NotificationPermissionDialog`), which is exactly wrong for a student who
  /// has just granted permission.
  Future<bool> requestPermission() async {
    final bool isGranted;
    try {
      isGranted = await requestPlatformPermission();
    } catch (e) {
      debugPrint('Failed to request notification permission: $e');
      return false;
    }

    if (isGranted) {
      // reconcile() resolves the push target itself and subscribes this
      // device to the student's saved topic intent - calling it here is
      // sufficient on its own. This used to call `_loadTopicSubscriptions()`,
      // which only populated the obsolete in-memory legacy map and created
      // no Appwrite subscriptions at all: a student who granted permission
      // from anywhere but the first-run prompt (e.g. the chat settings
      // toggle at `settings_screen_chat_tab.dart`, which calls only this
      // method) got a push target and nothing else - no content
      // notifications until the next launch, auth change, or campus change.
      //
      // Safe from recursion, which reconcile()'s queue would turn into a
      // deadlock: reconcile() checks the current permission but never calls
      // requestPermission() itself. Uses `_lastCampusId`, the same cache the
      // token-refresh path relies on, since this method has no campus id of
      // its own to pass in.
      try {
        await reconcile(campusId: _lastCampusId);
      } catch (e) {
        // reconcile() reports the failures it expects as a ReconcileOutcome;
        // this is whatever else escaped it. The grant is real regardless, and
        // the subscriptions are retried the next time reconcile() runs.
        debugPrint(
          'requestPermission: permission granted, but subscribing this '
          'device threw: $e',
        );
      }
    }

    return isGranted;
  }

  /// Check if notifications are currently enabled.
  ///
  /// A status that cannot be read reports `false`, and callers depend on that:
  /// the chat settings tab and the chat list both treat it as "not enabled
  /// yet" and offer to request permission. [reconcile] must not guess either
  /// way, so it calls [checkPlatformPermission] directly.
  Future<bool> areNotificationsEnabled() async {
    try {
      return await checkPlatformPermission();
    } catch (e) {
      debugPrint('Failed to check notification status: $e');
      return false;
    }
  }

  /// Whether the OS currently grants notification permission (including
  /// provisional on iOS). Unlike [areNotificationsEnabled], a status that
  /// cannot be read at all is rethrown rather than reported as not granted.
  ///
  /// A test seam, like [requestPlatformPermission]: there is no fake for
  /// Firebase's own settings read.
  @visibleForTesting
  Future<bool> checkPlatformPermission() async {
    final settings = await _firebaseMessaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// This device's FCM token, straight from Firebase, which throws when it
  /// cannot produce one (e.g. `SERVICE_NOT_AVAILABLE`).
  ///
  /// A test seam, like [requestPlatformPermission].
  @visibleForTesting
  Future<String?> fetchPlatformToken() => _firebaseMessaging.getToken();

  /// Invalidates this device's FCM token, so nothing bound to it — a push
  /// target on any account — can reach this device again. Firebase issues a
  /// fresh token on the next request. Needs no Appwrite session.
  ///
  /// A test seam, like [requestPlatformPermission].
  @visibleForTesting
  Future<void> deletePlatformToken() => _firebaseMessaging.deleteToken();

  /// Retries a token invalidation that sign-out could not complete (see
  /// [clearToken]), dropping this device's stale ids once it succeeds.
  ///
  /// Called by [initialize] at every launch. [reconcile] makes the same
  /// attempt before it resolves a push target, so one that fails here is
  /// retried then too.
  Future<void> retryPendingTokenInvalidation() => _enqueue<void>(
    'retryPendingTokenInvalidation',
    (run) async {
      await _settlePendingTokenInvalidation(run);
    },
    onTimeout: () {},
  );

  /// Establish this device's Appwrite push target for [token] and return its id.
  ///
  /// Ordered so the common case is a single call. The 409 branch is the one
  /// that matters: Appwrite rejects a second target for an identifier it
  /// already holds, which happens on every launch after the first. The old code
  /// swallowed that and left `_pushTargetId` null, so every later
  /// `subscribeToTopic` returned early and topic subscription could never work.
  ///
  /// [isCurrent] is how a queued run stops this acting once the run has been
  /// abandoned (see `_QueueRun.ownsState`): it is checked before every request
  /// and every write, and once it reports false this returns `null` having
  /// changed nothing more. A caller outside the queue omits it.
  Future<String?> resolvePushTarget(
    String token, {
    bool Function()? isCurrent,
  }) async {
    bool current() => isCurrent?.call() ?? true;

    final storedId = await _store.readTargetId();
    if (storedId != null) {
      if (!current()) return null;
      try {
        final target = await _account.updatePushTarget(
          targetId: storedId,
          identifier: token,
        );
        if (!current()) return null;
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

    if (!current()) return null;
    try {
      final target = await _account.createPushTarget(
        targetId: ID.unique(),
        identifier: token,
        providerId: kFcmProviderId,
      );
      return await _adoptTarget(target.$id, storedId, current)
          ? target.$id
          : null;
    } on AppwriteException catch (e) {
      if (e.code != 409) {
        debugPrint(
          'resolvePushTarget: create failed (${e.code}) ${e.message}',
        );
        return null;
      }
    }

    // 409: a target already holds this token. Find and adopt it.
    if (!current()) return null;
    try {
      final user = await _account.get();
      for (final target in user.targets) {
        if (target.identifier == token) {
          return await _adoptTarget(target.$id, storedId, current)
              ? target.$id
              : null;
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
  /// subscriber ids if it replaces a different one. Reports whether it did:
  /// once [current] reports false it stops, and writes nothing more.
  ///
  /// A subscriber belongs to a *target*. When the target changes identity the
  /// old subscribers are attached to something that no longer exists — but the
  /// stored map would still claim those topics are covered, so the next
  /// reconcile would compute an empty diff and the device would go silently
  /// unsubscribed. Clearing forces them to be recreated against the new target.
  Future<bool> _adoptTarget(
    String targetId,
    String? previousId,
    bool Function() current,
  ) async {
    if (previousId != null && previousId != targetId) {
      if (!current()) return false;
      await _store.writeSubscriberIds(const <String, String>{});
    }
    if (!current()) return false;
    await _store.writeTargetId(targetId);
    if (!current()) return false;
    _pushTargetId = targetId;
    return true;
  }

  /// The student's topic intent, migrating a pre-existing legacy map if that is
  /// all the account has.
  ///
  /// Rethrows when the preferences read itself fails — that must never be
  /// confused with "nothing saved yet", which is a normal state this method
  /// handles below without throwing (an absent [kTopicIntentPrefKey] simply
  /// falls through to [migrateLegacyIntent], which itself returns
  /// [kDefaultTopicIntent] when there is nothing to migrate either). A caller
  /// that cannot tell the two apart was the bug: it used to fabricate
  /// [kDefaultTopicIntent] on a failed read, show every switch on, and then —
  /// if the student touched one — persist that fabricated map over their real
  /// stored intent, destroying any genuine opt-out.
  Future<Map<String, bool>> loadTopicIntent() async {
    final Map<String, dynamic> data;
    try {
      data = (await _account.getPrefs()).data;
    } catch (e) {
      debugPrint('loadTopicIntent: could not read preferences: $e');
      rethrow;
    }

    final stored = decodeTopicSubscriptions(data[kTopicIntentPrefKey]);
    if (stored != null) {
      return <String, bool>{...kDefaultTopicIntent, ...stored}
        ..removeWhere((key, _) => !kDefaultTopicIntent.containsKey(key));
    }
    return migrateLegacyIntent(
      decodeTopicSubscriptions(data[kLegacyTopicSubscriptionsPrefKey]),
    );
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
  /// intent for [campusId], reporting what actually happened via
  /// [ReconcileOutcome] rather than swallowing every way this can come up
  /// short.
  ///
  /// Idempotent by construction — it diffs desired against observed rather than
  /// replaying toggles — so it is safe to call on every launch, and two devices
  /// on one account reconcile independently without coordinating.
  ///
  /// Runs one at a time on this device, in the queue it shares with
  /// [clearToken] (see [_queue]): a call made while another run is in
  /// progress waits for it, then reads fresh state. Each caller still receives
  /// its own run's outcome, or its own run's error — and
  /// [ReconcileOutcome.unavailable] if its run has not finished within
  /// [kNotificationRunTimeout].
  Future<ReconcileOutcome> reconcile({required String? campusId}) {
    // Cached at call time, before the run is even queued, so a later token
    // refresh — which has no campusId of its own to pass in — reconciles
    // against the most recent campus this method was actually asked to use.
    _lastCampusId = campusId;

    return _enqueue(
      'reconcile',
      (run) => _reconcileNow(run, campusId),
      onTimeout: () => ReconcileOutcome.unavailable,
    );
  }

  /// The tail of this device's queue: every [reconcile], every [clearToken],
  /// and the launch retry of a pending token invalidation.
  ///
  /// Callers overlap: the launch reconciler on every rebuild,
  /// `TopicIntentNotifier.setTopic`, the token-refresh listener,
  /// [requestPermission], and the first-run prompt. Each run reads the stored
  /// subscriber map, diffs it, and writes its own result back, so two
  /// overlapping runs let the last write drop a subscriber id the other just
  /// created. That subscriber then exists server-side with no local id: every
  /// later run tries to create it again and gets a 409, and the device can
  /// never unsubscribe from that topic. The client SDK cannot list subscribers,
  /// so the id is unrecoverable — which is why runs must never overlap at all,
  /// rather than being repaired afterwards.
  ///
  /// Sign-out belongs in the same queue. [clearToken] reads and clears the
  /// same stored map, so a reconcile overlapping it — the launch reconciler,
  /// or one a campus change started — could write ids back after it had
  /// cleared them, or delete around it.
  ///
  /// Each link swallows its own outcome before being stored here, so a run
  /// that throws cannot leave this future rejected and wedge every run queued
  /// behind it. The run's own caller still receives the error. A run that
  /// hangs is abandoned at its bound for the same reason (see [_enqueue]).
  Future<void> _queue = Future<void>.value();

  /// The generation of the run allowed to act on shared state: the run in
  /// progress, until it is abandoned. See [_QueueRun.ownsState].
  int _generation = 0;

  /// How many times [clearToken] has been called. See
  /// [_QueueRun.signOutRequested].
  int _signOutRequests = 0;

  /// Queues [body] behind every run already queued, and abandons it if it has
  /// not finished within [kNotificationRunTimeout], completing with
  /// [onTimeout]'s value instead so the runs behind it can start.
  ///
  /// Abandoning a run cannot stop the request it is awaiting, which may still
  /// answer later. What stops the run acting on that answer is its
  /// generation: each run takes a new one as it starts, and an abandoned run's
  /// is retired, so [_QueueRun.ownsState] is false for it from then on. Every
  /// request a run starts and every write it makes is preceded by that check,
  /// so an abandoned run stops at the next one, writing nothing that could
  /// overwrite what the runs after it recorded.
  Future<T> _enqueue<T>(
    String label,
    Future<T> Function(_QueueRun run) body, {
    required T Function() onTimeout,
  }) {
    final run = _QueueRun(this);
    final result = _queue.then((_) {
      run.generation = ++_generation;
      return body(run).timeout(
        kNotificationRunTimeout,
        onTimeout: () {
          if (run.ownsState) _generation++;
          debugPrint(
            '$label: not finished after ${kNotificationRunTimeout.inSeconds}s; '
            'abandoned so the runs queued behind it can start',
          );
          return onTimeout();
        },
      );
    });
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Settles a pending token invalidation, if a sign-out left one (see
  /// [clearToken]), and reports whether [run] may now resolve a push target.
  ///
  /// Never while one is pending: this device's token may still be bound to the
  /// signed-out account's target, and a target resolved or created with it —
  /// for the next student to sign in, say — would bind their pushes to the
  /// same token, so this device would receive both accounts' pushes. Only
  /// invalidating the token breaks that binding without the old session, so it
  /// is retried here, on every run, until it succeeds.
  Future<bool> _settlePendingTokenInvalidation(_QueueRun run) async {
    // A run queued before sign-out was asked for stands down: settling would
    // clear the invalidation sign-out has just recorded, and forget the ids
    // its cleanup, queued behind this run, still has to delete.
    if (run.signOutRequested) return false;

    final bool pending;
    try {
      pending = await _store.readPendingTokenInvalidation();
    } catch (e) {
      debugPrint(
        'Could not read whether a token invalidation is pending; not '
        'resolving a push target ($e)',
      );
      return false;
    }
    if (!pending) return true;

    if (!run.ownsState) return false;
    try {
      await deletePlatformToken();
    } catch (e) {
      debugPrint(
        'The FCM token a sign-out left behind still cannot be invalidated; '
        'push stays unavailable on this device until it can ($e)',
      );
      return false;
    }

    if (!run.ownsState) return false;
    _fcmToken = null;
    try {
      // The stale target id goes with the subscriber ids: updating that target
      // would bind the fresh token to the signed-out account all over again.
      await _store.clear();
    } catch (e) {
      debugPrint('Could not clear the ids a sign-out left behind: $e');
      return false;
    }
    return true;
  }

  /// One [reconcile] run. Only ever started by [reconcile]'s queue.
  Future<ReconcileOutcome> _reconcileNow(
    _QueueRun run,
    String? campusId,
  ) async {
    if (!await _settlePendingTokenInvalidation(run)) {
      return ReconcileOutcome.unavailable;
    }

    // Not areNotificationsEnabled(), which reports a check that errors as "not
    // granted". permissionDenied tells a caller the student must go and enable
    // notifications, and a check that could not run says nothing of the sort -
    // the permission dialog reads this outcome straight after a grant.
    final bool permitted;
    try {
      permitted = await checkPlatformPermission();
    } catch (e) {
      debugPrint(
        'reconcile: could not check notification permission; skipping ($e)',
      );
      return ReconcileOutcome.unavailable;
    }
    if (!permitted) {
      debugPrint('reconcile: notifications not permitted; intent kept for later');
      return ReconcileOutcome.permissionDenied;
    }

    // The launch fetch in initialize() can fail and leave no cached token, and
    // Firebase then throws here too (SERVICE_NOT_AVAILABLE, no network). That
    // is reported like a missing token rather than thrown into every caller.
    var token = _fcmToken;
    if (token == null) {
      try {
        token = await fetchPlatformToken();
      } catch (e) {
        debugPrint('reconcile: could not get an FCM token; skipping ($e)');
        return ReconcileOutcome.unavailable;
      }
    }
    if (token == null) {
      debugPrint('reconcile: no FCM token; skipping');
      return ReconcileOutcome.unavailable;
    }

    // Checked again now that the permission and token reads have been
    // awaited: a sign-out asked for in the meantime would otherwise have this
    // run register a push target for the account on its way out.
    if (run.signOutRequested) {
      debugPrint('reconcile: sign-out requested; not registering this device');
      return ReconcileOutcome.unavailable;
    }
    if (!run.ownsState) return ReconcileOutcome.unavailable;
    _fcmToken = token;

    final targetId = await resolvePushTarget(
      token,
      isCurrent: () => run.ownsState,
    );
    if (!run.ownsState) return ReconcileOutcome.unavailable;
    if (targetId == null) {
      debugPrint('reconcile: no push target; skipping subscription changes');
      return ReconcileOutcome.unavailable;
    }

    final Map<String, bool> intent;
    try {
      intent = await loadTopicIntent();
    } catch (e) {
      // Reconciling against a guessed intent is exactly the harm this type
      // exists to prevent: it could subscribe a student to a topic they had
      // deliberately turned off. Abort instead, and retry on the next launch,
      // auth change, or campus change.
      debugPrint('reconcile: could not read topic intent; aborting ($e)');
      return ReconcileOutcome.unavailable;
    }

    final desired = appwriteTopicIdsFor(intent: intent, campusId: campusId);
    final current = await _store.readSubscriberIds();
    final diff = computeTopicDiff(desired: desired, current: current);
    if (diff.isEmpty) return ReconcileOutcome.applied;

    final updated = Map<String, String>.from(current);
    var hadFailure = false;

    // Each change is recorded as soon as it lands, not once at the end. A run
    // abandoned at its bound may write nothing afterwards (see [_enqueue]), so
    // a subscriber created early in a run that then hung would otherwise exist
    // on the server with no id on this device — unrecoverably, since the
    // client SDK cannot list subscribers.
    for (final topicId in diff.toCreate) {
      if (!run.ownsState) return ReconcileOutcome.unavailable;
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
        hadFailure = true;
        continue;
      }
      if (!run.ownsState) return ReconcileOutcome.unavailable;
      await _store.writeSubscriberIds(updated);
    }

    for (final topicId in diff.toDelete) {
      final subscriberId = updated[topicId];
      if (subscriberId == null) continue;
      if (!run.ownsState) return ReconcileOutcome.unavailable;
      try {
        await _messaging.deleteSubscriber(
          topicId: topicId,
          subscriberId: subscriberId,
        );
      } on AppwriteException catch (e) {
        if (e.code != 404) {
          debugPrint(
            'reconcile: unsubscribe from $topicId failed '
            '(${e.code}) ${e.message}',
          );
          hadFailure = true;
          continue;
        }
        // Already gone server-side; stop tracking it.
      }
      updated.remove(topicId);
      if (!run.ownsState) return ReconcileOutcome.unavailable;
      await _store.writeSubscriberIds(updated);
    }

    return hadFailure
        ? ReconcileOutcome.partiallyFailed
        : ReconcileOutcome.applied;
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
  /// The push target goes first: it needs the session, which sign-out deletes
  /// straight afterwards, and deleting it kills every subscriber attached to it
  /// in one request. The subscribers are deleted one by one only when the
  /// target survives, since they would otherwise go on delivering topic pushes
  /// here. Then the FCM token is invalidated, which needs no session.
  ///
  /// The device counts as detached once either the target deletion or the
  /// token invalidation succeeds: a deleted target reaches nothing, and a dead
  /// token is reached by nothing. Only then are the stored ids cleared. If
  /// neither succeeded, the target is still bound to a live token and this
  /// device would keep receiving the signed-out student's pushes. Nothing
  /// Appwrite-side can be retried without their session, but the invalidation
  /// can, so the ids are kept and a pending invalidation is recorded for
  /// [retryPendingTokenInvalidation] and [reconcile] to retry — each before it
  /// resolves any push target.
  ///
  /// That record is written when this is called, before the cleanup waits its
  /// turn in the queue: `AuthNotifier.logout` stops waiting after
  /// [kSignOutCleanupTimeout] and deletes the session regardless, possibly
  /// before this cleanup has even started, and the record must exist by then.
  /// It is cleared only once the device is known to be detached.
  ///
  /// Every await is guarded, so no storage or network failure here can
  /// propagate and block sign-out. Intent is deliberately left in account
  /// preferences — it is per-user, and the next login reconciles from it.
  Future<void> clearToken() {
    // Claimed synchronously, so a reconcile already queued stands down rather
    // than registering this device for the account that is signing out (see
    // [_QueueRun.signOutRequested]).
    _signOutRequests++;
    final recorded = _recordPendingTokenInvalidation();
    return _enqueue<void>(
      'clearToken',
      (run) => _clearTokenNow(run, recorded),
      onTimeout: () {},
    );
  }

  Future<void> _recordPendingTokenInvalidation() async {
    try {
      await _store.writePendingTokenInvalidation();
    } catch (e) {
      debugPrint('clearToken: could not record the pending invalidation: $e');
    }
  }

  /// One [clearToken] run. Only ever started by [clearToken]'s queue.
  Future<void> _clearTokenNow(_QueueRun run, Future<void> recorded) async {
    await recorded;
    if (!run.ownsState) return;

    _pushTargetId = null;
    _topicSubscriptions.clear();
    _topicSubscriberIds.clear();
    // Otherwise a sign-in by a different student later in the same session
    // would see `ensureTopicSubscriptionsLoaded()` short-circuit on this flag
    // and serve them whatever was left over in memory from the account that
    // just signed out.
    _topicSubscriptionsLoaded = false;

    String? targetId;
    try {
      targetId = await _store.readTargetId();
    } catch (e) {
      debugPrint('clearToken: could not read target id: $e');
    }
    var targetDeleted = false;
    if (targetId != null) {
      if (!run.ownsState) return;
      try {
        await _account.deletePushTarget(targetId: targetId);
        targetDeleted = true;
      } catch (e) {
        debugPrint('clearToken: could not delete target $targetId: $e');
      }
    }

    if (!targetDeleted) {
      var subscriberIds = const <String, String>{};
      try {
        subscriberIds = await _store.readSubscriberIds();
      } catch (e) {
        debugPrint('clearToken: could not read subscriber ids: $e');
      }
      for (final entry in subscriberIds.entries) {
        if (!run.ownsState) return;
        try {
          await _messaging.deleteSubscriber(
            topicId: entry.key,
            subscriberId: entry.value,
          );
        } catch (e) {
          debugPrint('clearToken: could not remove ${entry.key}: $e');
        }
      }
    }

    if (!run.ownsState) return;
    var tokenInvalidated = false;
    try {
      await deletePlatformToken();
      tokenInvalidated = true;
    } catch (e) {
      debugPrint('clearToken: could not delete the FCM token: $e');
    }

    if (!run.ownsState) return;
    if (tokenInvalidated) _fcmToken = null;
    if (targetDeleted || tokenInvalidated) {
      try {
        await _store.clear();
      } catch (e) {
        debugPrint('clearToken: could not clear the local store: $e');
      }
      return;
    }

    debugPrint(
      'clearToken: neither the push target nor the FCM token could be '
      'removed; keeping the ids and retrying the invalidation at next launch',
    );
    try {
      // Again, in case the write made as sign-out began had failed.
      await _store.writePendingTokenInvalidation();
    } catch (e) {
      debugPrint('clearToken: could not record the pending invalidation: $e');
    }
  }
}

/// One run of [NotificationService]'s queue: a reconcile, a sign-out cleanup,
/// or a launch retry of a pending token invalidation.
class _QueueRun {
  _QueueRun(this._service) : _signOutsWhenQueued = _service._signOutRequests;

  final NotificationService _service;
  final int _signOutsWhenQueued;

  /// Assigned by `NotificationService._enqueue` as the run starts.
  int generation = -1;

  /// Whether this run may still act: write the device store or the service's
  /// cached token and target, or start a request.
  ///
  /// False from the moment the run is abandoned at its bound, and from then
  /// on: a later run has taken over, and anything this one wrote could
  /// overwrite what that run recorded.
  ///
  /// A run checks it immediately before each write. That is enough because a
  /// `SharedPreferences` write takes effect when it is called — its cache is
  /// updated synchronously — and all the store awaits before that call is an
  /// instance the run has already loaded, which completes as a microtask. The
  /// timer that abandons a run cannot fire in between.
  bool get ownsState => _service._generation == generation;

  /// Whether [NotificationService.clearToken] has been called since this run
  /// was queued.
  bool get signOutRequested =>
      _service._signOutRequests != _signOutsWhenQueued;
}
