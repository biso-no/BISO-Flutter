import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'member_pass_provider.dart';
import 'scan_display.dart';
import 'scan_gate.dart';
import 'scanner_access_provider.dart';

/// A different feel per result, so staff notice without looking.
final scanHapticsProvider = Provider<void Function(ScanTone)>(
  (ref) => (tone) {
    switch (tone) {
      case ScanTone.green:
        unawaited(HapticFeedback.mediumImpact());
      case ScanTone.orange || ScanTone.amber:
        unawaited(HapticFeedback.heavyImpact());
      case ScanTone.red:
        unawaited(HapticFeedback.vibrate());
      case ScanTone.grey:
        unawaited(HapticFeedback.selectionClick());
    }
  },
);

final scannerControllerProvider =
    NotifierProvider.autoDispose<ScannerController, ScannerDisplay>(
      ScannerController.new,
    );

/// Turns camera reads into scans and scans into what the screen shows.
/// Scanned strings are held only for the request and never logged.
class ScannerController extends AutoDisposeNotifier<ScannerDisplay> {
  static const resultDuration = Duration(seconds: 3);

  final ScanGate _gate = ScanGate();
  Timer? _dismissTimer;
  bool _disposed = false;

  @override
  ScannerDisplay build() {
    ref.onDispose(() {
      _disposed = true;
      _dismissTimer?.cancel();
    });
    return const ScannerIdle();
  }

  Future<void> onDetected(String raw) async {
    final code = raw.trim();
    if (code.isEmpty) return;
    if (!_gate.admit(code, ref.read(memberPassClockProvider)())) return;
    if (code.length > maxScanCodeLength) {
      _show(overlongCodeResult);
      return;
    }
    state = const ScannerChecking();
    final api = ref.read(memberPassApiProvider);
    ScannerDisplay next;
    try {
      next = mapScanOutcome(await api.scan(code));
    } catch (error) {
      next = mapScanError(error);
    }
    if (_disposed) return;
    if (next is ScannerResult) {
      _show(next);
    } else {
      state = next;
      ref.invalidate(scannerAccessProvider);
    }
  }

  void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    if (state is ScannerResult) {
      _gate.finish();
      state = const ScannerIdle();
    }
  }

  void _show(ScannerResult result) {
    state = result;
    ref.read(scanHapticsProvider)(result.tone);
    _dismissTimer?.cancel();
    _dismissTimer = Timer(resultDuration, dismiss);
  }
}
