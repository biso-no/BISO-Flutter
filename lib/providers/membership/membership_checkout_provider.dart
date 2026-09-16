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
    unawaited(_restorePending());
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
        // Detached from this call: nothing here awaits it, so nothing here
        // can catch it either. Handle its error explicitly rather than let
        // it surface as unhandled — the same background check keeps running
        // long after `start` has returned.
        unawaited(
          _ref.read(membershipOverviewProvider.notifier).refresh().catchError((
            Object refreshError,
          ) {
            logPrint(
              '🎫 Could not refresh the membership overview after a '
              'checkout refusal: $refreshError',
            );
          }),
        );
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
  Future<void> resolvePending({String? orderId, bool cancelled = false}) async {
    final id = orderId ?? _pendingOrderId;
    if (id == null || _resolving) return;
    _resolving = true;
    try {
      final order = await _ref.read(shopApiClientProvider).fetchOrder(id);
      if (!mounted) return;

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

  /// Payment is in; fulfilment has run server-side. Re-verify until the new
  /// membership shows, which proves it reached 24SevenOffice.
  Future<void> _activate(String orderId) async {
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
      // A cold launch is not a resume, so resolve now rather than waiting for
      // the next time the app comes back to the foreground.
      await resolvePending();
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
