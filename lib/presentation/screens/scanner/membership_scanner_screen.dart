import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/navigation_utils.dart';
import '../../../core/utils/oslo_time.dart';
import '../../../data/models/member_pass.dart';
import '../../../data/services/scanner_camera.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/member_pass/scan_display.dart';
import '../../../providers/member_pass/scanner_controller.dart';
import '../../widgets/member_pass/pass_colors.dart';

/// Full-screen camera. Each result covers the whole screen, so door staff
/// read it at a glance.
class MembershipScannerScreen extends ConsumerStatefulWidget {
  const MembershipScannerScreen({super.key, required this.access});

  final ScannerAccess access;

  @override
  ConsumerState<MembershipScannerScreen> createState() =>
      _MembershipScannerScreenState();
}

class _MembershipScannerScreenState
    extends ConsumerState<MembershipScannerScreen>
    with WidgetsBindingObserver {
  late final ScannerCamera _camera = ref.read(scannerCameraFactoryProvider)();

  /// Whether the camera was stopped for backgrounding specifically (as
  /// opposed to stopped for a visible result). Guards repeat stop
  /// calls across inactive/hidden/paused, and gates the foreground resume.
  bool _backgroundStopped = false;

  /// Kept in step by [didChangeAppLifecycleState]; a dismiss reached via
  /// the result's own auto-dismiss timer is not lifecycle-aware, so it
  /// must consult this rather than assume it is running in the foreground.
  bool _foreground = _isForeground(WidgetsBinding.instance.lifecycleState);

  static bool _isForeground(AppLifecycleState? state) =>
      state == null || state == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _resumeFromBackground();
    } else {
      _stopForBackground();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_camera.dispose());
    super.dispose();
  }

  /// Stops the camera the moment the app leaves the foreground. Passing our
  /// own controller to `MobileScanner` opts out of its built-in lifecycle
  /// handling, so this screen must do it. Guards against inactive, hidden
  /// and paused firing in a row.
  void _stopForBackground() {
    if (_backgroundStopped) return;
    _backgroundStopped = true;
    unawaited(_guardedCameraCall(_camera.stop()));
  }

  /// Restarts a camera stopped for the background, once the app is back and
  /// no result currently covers the screen — a visible result keeps the
  /// camera off regardless, and dismissing it is handled by
  /// [_resumeFromResult].
  void _resumeFromBackground() {
    if (!_backgroundStopped) return;
    if (ref.read(scannerControllerProvider) is ScannerResult) return;
    _backgroundStopped = false;
    unawaited(_guardedCameraCall(_camera.resume()));
  }

  /// A result was dismissed (by a tap or its own auto-dismiss timer, which
  /// is not lifecycle-aware and can fire while backgrounded). Resumes only
  /// if the app is actually in the foreground; otherwise the camera stays
  /// off and [_resumeFromBackground] finishes the job on the next
  /// `resumed` event.
  void _resumeFromResult() {
    if (!_foreground) {
      _backgroundStopped = true;
      return;
    }
    _backgroundStopped = false;
    unawaited(_guardedCameraCall(_camera.resume()));
  }

  /// `MobileScannerController` can throw (still starting, no permission,
  /// already disposed) from any start/stop call; the next lifecycle or
  /// scan event retries, so a failure here is silently dropped. Never
  /// touches scanned data.
  Future<void> _guardedCameraCall(Future<void> action) =>
      action.catchError((_) {});

  void _close(ScannerCloseReason reason) {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.maybeOf(context);
    NavigationUtils.safeGoBack(context, fallbackRoute: '/explore');
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          reason == ScannerCloseReason.noAccess
              ? l10n.scannerNoAccess
              : l10n.scannerSignedOut,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = ref.read(scannerControllerProvider.notifier);
    ref.listen(scannerControllerProvider, (previous, next) {
      if (next is ScannerResult && previous is! ScannerResult) {
        // Stopped, not paused: mobile_scanner's stop() does nothing on a
        // paused camera, so a pause would keep the session while
        // backgrounded.
        unawaited(_guardedCameraCall(_camera.stop()));
      } else if (next is ScannerIdle && previous is ScannerResult) {
        _resumeFromResult();
      } else if (next is ScannerClosed) {
        _close(next.reason);
      }
    });
    final display = ref.watch(scannerControllerProvider);

    return Scaffold(
      backgroundColor: PassColors.scannerBackground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _camera.preview(
            onCode: (code) => unawaited(controller.onDetected(code)),
            onError: (context) => _CameraError(text: l10n.scannerCameraError),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopBar(
              access: widget.access,
              onClose: () => NavigationUtils.safeGoBack(
                context,
                fallbackRoute: '/explore',
              ),
            ),
          ),
          if (display is ScannerIdle)
            Positioned(
              left: 24,
              right: 24,
              bottom: 48,
              child: SafeArea(
                child: Text(
                  l10n.scannerPointCamera,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: PassColors.cardInk),
                ),
              ),
            ),
          if (display is ScannerChecking)
            const Center(
              child: CupertinoActivityIndicator(
                radius: 18,
                color: PassColors.cardInk,
              ),
            ),
          if (display is ScannerResult)
            Positioned.fill(
              child: ScanResultOverlay(
                result: display,
                onTap: controller.dismiss,
              ),
            ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.access, required this.onClose});

  final ScannerAccess access;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final expiresAt = access.expiresAt;
    final dayColor = access.dayColor.color;
    return ColoredBox(
      color: PassColors.scannerBackground.withValues(alpha: 0.6),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: onClose,
                icon: const Icon(
                  CupertinoIcons.xmark,
                  color: PassColors.cardInk,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.scannerTitle,
                      style: text.titleMedium?.copyWith(
                        color: PassColors.cardInk,
                      ),
                    ),
                    if (expiresAt != null)
                      Text(
                        l10n.scannerAccessUntil(
                          DateFormat.MMMd(
                            locale,
                          ).add_Hm().format(osloWallClock(expiresAt)),
                        ),
                        style: text.bodySmall?.copyWith(
                          color: PassColors.cardMuted,
                        ),
                      ),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: dayColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: Text(
                    dayColorName(l10n, access.dayColor.name),
                    style: text.labelLarge?.copyWith(
                      color: PassColors.inkOn(dayColor),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A scan result over the whole screen, in its tone.
class ScanResultOverlay extends StatelessWidget {
  const ScanResultOverlay({
    super.key,
    required this.result,
    required this.onTap,
  });

  final ScannerResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final background = PassColors.scanTone(result.tone);
    final ink = PassColors.inkOn(background);
    final expiry = result.expiryDate;
    final icon = switch (result.tone) {
      ScanTone.green => CupertinoIcons.checkmark_circle_fill,
      ScanTone.orange => CupertinoIcons.arrow_counterclockwise_circle_fill,
      ScanTone.amber => CupertinoIcons.person_crop_rectangle_fill,
      ScanTone.red => CupertinoIcons.xmark_circle_fill,
      ScanTone.grey => CupertinoIcons.exclamationmark_circle_fill,
    };

    return Semantics(
      liveRegion: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ColoredBox(
          color: background,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 112, color: ink),
                  const SizedBox(height: 20),
                  Text(
                    scanMessageText(l10n, result),
                    textAlign: TextAlign.center,
                    style: text.headlineMedium?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  if (result.name != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      result.name!,
                      textAlign: TextAlign.center,
                      style: text.titleLarge?.copyWith(color: ink),
                    ),
                  ],
                  if (result.membershipName != null)
                    Text(
                      result.membershipName!,
                      style: text.titleMedium?.copyWith(color: ink),
                    ),
                  if (expiry != null)
                    Text(
                      l10n.memberPassValidUntil(
                        DateFormat.yMMMd(locale).format(expiry),
                      ),
                      style: text.titleMedium?.copyWith(color: ink),
                    ),
                  const SizedBox(height: 32),
                  Text(
                    l10n.scannerTapToContinue,
                    style: text.bodyMedium?.copyWith(color: ink),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: PassColors.cardInk),
        ),
      ),
    );
  }
}
