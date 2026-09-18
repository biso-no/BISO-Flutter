import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/logging/print_migration.dart';
import '../../data/models/payment_provider.dart';
import '../../data/models/shop_order.dart';
import '../../data/services/membership_api_client.dart';
import '../shop/cart_provider.dart';
import '../shop/checkout_provider.dart';
import 'membership_overview_provider.dart';

enum MembershipPurchasePhase {
  idle,
  starting,
  awaitingPayment,
  activating,
  activated,
  activationDelayed,
  cancelled,
  failed,
}

class MembershipPurchaseState extends Equatable {
  final MembershipPurchasePhase phase;
  final String? orderId;
  final String? message;

  const MembershipPurchaseState({
    this.phase = MembershipPurchasePhase.idle,
    this.orderId,
    this.message,
  });

  @override
  List<Object?> get props => [phase, orderId, message];
}

typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);

/// Opens a payment page outside the app: Vipps needs to hand off to its own
/// app, and a card form belongs in a real browser with the buyer's autofill.
final membershipUrlLauncherProvider = Provider<ExternalUrlLauncher>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Drives a membership purchase and follows the payment home.
///
/// The student pays outside the app and the app may be evicted meanwhile, so
/// the order is remembered on disk and resolved on construction (a cold
/// launch), on every return to the foreground, and when the return deep link
/// arrives. The order is read through `GET /api/payment/orders/:id`, which
/// reconciles with the provider and runs fulfilment (24SevenOffice customer,
/// category and invoice) before answering, so a "paid" here is real.
class MembershipCheckoutController
    extends StateNotifier<MembershipPurchaseState> {
  MembershipCheckoutController(
    this._ref, {
    Duration activationPollInterval = const Duration(seconds: 10),
    int activationAttempts = 10,
  }) : _activationPollInterval = activationPollInterval,
       _activationAttempts = activationAttempts,
       super(const MembershipPurchaseState()) {
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(resolvePending()),
    );
    _restored = _restorePending();
    // A cold launch is not a resume, so resolve now rather than waiting for
    // the next time the app comes back to the foreground. `resolvePending`
    // itself waits on `_restored`, so calling it immediately is safe even
    // though restoration is still in flight.
    unawaited(resolvePending());
  }

  final Ref _ref;
  final Duration _activationPollInterval;

  /// Polls long enough (about 100 s by default) to outlast the server's
  /// once-a-minute refresh floor on the membership check.
  final int _activationAttempts;
  late final AppLifecycleListener _lifecycle;

  static const String _pendingOrderKey = 'membership_pending_order_id';
  static const String _pendingStartedKey = 'membership_pending_started_at';
  static const Duration _pendingMaxAge = Duration(hours: 2);

  /// Completes once the persisted marker, if any, has been read back.
  ///
  /// `resolvePending` awaits this first. Without it, a deep link landing at
  /// cold launch — before the marker has loaded — would be checked against a
  /// `_pendingOrderId` that is still `null`, collapsing "a different order is
  /// pending" into "nothing is pending" and defeating the guard below.
  late final Future<void> _restored;

  String? _pendingOrderId;
  bool _resolving = false;

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> start({
    required PaymentProvider provider,
    required String planId,
    required String campusId,
  }) async {
    state = const MembershipPurchaseState(
      phase: MembershipPurchasePhase.starting,
    );
    try {
      final started = await _ref
          .read(membershipApiClientProvider)
          .startCheckout(
            provider: provider,
            planId: planId,
            campusId: campusId,
          );
      await _rememberPending(started.orderId);

      final opened = await _ref.read(membershipUrlLauncherProvider)(
        Uri.parse(started.checkoutUrl),
      );
      if (!mounted) return;
      if (!opened) {
        // The order stays payable: starting again reuses the same session
        // within the server's idempotency window.
        state = MembershipPurchaseState(
          phase: MembershipPurchasePhase.failed,
          orderId: started.orderId,
          message: 'We could not open your payment provider.',
        );
        return;
      }
      state = MembershipPurchaseState(
        phase: MembershipPurchasePhase.awaitingPayment,
        orderId: started.orderId,
      );
    } on MembershipApiException catch (error) {
      if (!mounted) return;
      state = MembershipPurchaseState(
        phase: MembershipPurchasePhase.failed,
        message: error.message,
      );
      if (error.isAlreadyCovered || error.isUnavailable) {
        _recheckMembership();
      }
      if (error.isProviderDisabled) {
        _ref.invalidate(paymentProvidersProvider);
      }
    } catch (error) {
      logPrint('🎫 Membership checkout failed to start: $error');
      if (!mounted) return;
      state = const MembershipPurchaseState(
        phase: MembershipPurchasePhase.failed,
        message: 'We could not start the payment. Please try again.',
      );
    }
  }

  /// Checks on the payment the student left to make.
  ///
  /// [orderId] and [cancelled] come from the return deep link; without them
  /// the remembered order is checked. Silent on network failure, so the
  /// marker stays for the next attempt.
  ///
  /// The state and the marker belong to the order actually pending. A deep
  /// link naming a different one (an old return link, flushed late after a
  /// newer purchase started) is ignored outright, and an answer that lands
  /// after a newer purchase started is dropped. Either way the membership is
  /// re-checked, in case that other order was paid.
  ///
  /// With nothing pending — the student started over, or the marker expired
  /// (it lasts two hours; a card checkout can last a day) — the order is
  /// still read. An unpaid answer is dropped: that attempt was given up. A
  /// paid one is shown landing exactly as for the pending order, polling
  /// until the membership appears. A single re-check would not do: the
  /// server answers a forced refresh from its cache when it re-checked the
  /// student within the last minute, and "Start over" and starting a
  /// checkout both use that minute up.
  Future<void> resolvePending({String? orderId, bool cancelled = false}) async {
    await _restored;
    final id = orderId ?? _pendingOrderId;
    if (id == null) return;
    if (_pendingOrderId != null && _pendingOrderId != id) {
      logPrint(
        '🎫 Ignoring a resolve for $id — $_pendingOrderId is the order '
        'actually pending.',
      );
      _recheckMembership();
      return;
    }
    if (_resolving) return;
    _resolving = true;
    try {
      // With nothing pending this still fetches: the read makes the server
      // reconcile the order with the provider, and its answer decides below
      // whether there is a payment to show.
      final order = await _ref.read(shopApiClientProvider).fetchOrder(id);
      if (!mounted) return;
      final pending = _pendingOrderId;
      if (pending == null && order.status.isSuccessful) {
        // Paid, with no marker to clear: show it landing all the same.
        await _activate(id);
        return;
      }
      if (pending != id) {
        logPrint(
          '🎫 Dropping the answer for $id — '
          '${pending == null ? 'that attempt was given up' : '$pending is the order pending'}.',
        );
        _recheckMembership();
        return;
      }

      if (order.status.isSuccessful) {
        await _clearPending();
        await _activate(id);
      } else if (order.status == ShopOrderStatus.failed) {
        await _clearPending();
        state = MembershipPurchaseState(
          phase: MembershipPurchasePhase.failed,
          orderId: id,
          message: 'The payment did not go through. You have not been charged.',
        );
      } else if (order.status == ShopOrderStatus.refunded) {
        await _clearPending();
        state = MembershipPurchaseState(
          phase: MembershipPurchasePhase.failed,
          orderId: id,
          message: 'This payment was refunded.',
        );
      } else if (order.status == ShopOrderStatus.cancelled || cancelled) {
        await _clearPending();
        state = MembershipPurchaseState(
          phase: MembershipPurchasePhase.cancelled,
          orderId: id,
        );
      } else {
        state = MembershipPurchaseState(
          phase: MembershipPurchasePhase.awaitingPayment,
          orderId: id,
        );
      }
    } catch (error) {
      logPrint('🎫 Could not resolve the membership payment: $error');
    } finally {
      _resolving = false;
    }
  }

  /// Returns the screen to its normal state after an outcome was shown.
  void dismissOutcome() => state = const MembershipPurchaseState();

  /// Gives up on following a payment the student walked away from, so they
  /// can start a new one instead of staring at a disabled Pay button.
  ///
  /// This does not cancel anything: the order lives on the server and only
  /// the provider can settle it. If it does settle, its return link still
  /// shows the payment landing (see [resolvePending]), and the re-check this
  /// starts may show the membership sooner — so the app never tells the
  /// student the payment is cancelled, only that it has stopped waiting.
  ///
  /// The state is dropped first, synchronously, so the screen unlocks on the
  /// very next frame rather than after the disk write.
  Future<void> abandonPending() async {
    state = const MembershipPurchaseState();
    // The payment may have gone through after all, and the student is about
    // to be offered a plan again: ask now rather than let them pay twice.
    _recheckMembership();
    // A marker still being read back from disk must not reappear after this.
    await _restored;
    await _clearPending();
  }

  /// Re-verifies the membership in the background, forcing the server past
  /// its own cache. Detached — nothing here waits on it, so nothing here
  /// could catch its error either; it is handled explicitly instead.
  void _recheckMembership() {
    unawaited(
      _ref
          .read(membershipOverviewProvider.notifier)
          .refresh(force: true)
          .catchError((Object error) {
            logPrint('🎫 Could not re-check the membership: $error');
          }),
    );
  }

  /// Payment is in; fulfilment has run server-side. Re-verify until the new
  /// membership shows, which proves it reached 24SevenOffice.
  Future<void> _activate(String orderId) async {
    if (!mounted) return;
    state = MembershipPurchaseState(
      phase: MembershipPurchasePhase.activating,
      orderId: orderId,
    );
    final overview = _ref.read(membershipOverviewProvider.notifier);
    for (var attempt = 0; attempt < _activationAttempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(_activationPollInterval);
      }
      if (!mounted) return;
      await overview.refresh();
      if (_ref.read(membershipOverviewProvider).valueOrNull?.isMember == true) {
        state = MembershipPurchaseState(
          phase: MembershipPurchasePhase.activated,
          orderId: orderId,
        );
        return;
      }
    }
    if (!mounted) return;
    state = MembershipPurchaseState(
      phase: MembershipPurchasePhase.activationDelayed,
      orderId: orderId,
      message:
          'Your payment is confirmed. Your membership can take a few minutes '
          'to show up here.',
    );
  }

  Future<void> _restorePending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final orderId = prefs.getString(_pendingOrderKey);
      final startedAt = prefs.getInt(_pendingStartedKey);
      if (orderId == null || orderId.isEmpty || startedAt == null) return;
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(startedAt),
      );
      if (age > _pendingMaxAge) {
        await _clearPending();
        return;
      }
      _pendingOrderId = orderId;
    } catch (error) {
      logPrint('🎫 Failed to restore the membership payment: $error');
    }
  }

  Future<void> _rememberPending(String orderId) async {
    _pendingOrderId = orderId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingOrderKey, orderId);
      await prefs.setInt(
        _pendingStartedKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (error) {
      logPrint('🎫 Failed to remember the membership payment: $error');
    }
  }

  /// Drops the marker, in memory first (synchronously) so a second resolution
  /// racing this one finds nothing to act on.
  Future<void> _clearPending() async {
    _pendingOrderId = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingOrderKey);
      await prefs.remove(_pendingStartedKey);
    } catch (error) {
      logPrint('🎫 Failed to clear the membership payment: $error');
    }
  }
}

final membershipCheckoutControllerProvider =
    StateNotifierProvider<
      MembershipCheckoutController,
      MembershipPurchaseState
    >(MembershipCheckoutController.new);
