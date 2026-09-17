import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// The camera behind the scanner, so the screen can be tested without one.
abstract interface class ScannerCamera {
  Widget preview({
    required void Function(String code) onCode,
    required WidgetBuilder onError,
  });

  Future<void> resume();
  Future<void> stop();
  Future<void> dispose();
}

/// QR codes only. This controller is passed to [MobileScanner] explicitly,
/// so `mobile_scanner` does not manage the app lifecycle itself (its
/// `useAppLifecycleState` only applies when it owns the controller); the
/// screen that holds this camera handles backgrounding instead.
class MobileScannerCamera implements ScannerCamera {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  @override
  Widget preview({
    required void Function(String code) onCode,
    required WidgetBuilder onError,
  }) {
    return MobileScanner(
      controller: _controller,
      onDetect: (capture) {
        for (final barcode in capture.barcodes) {
          final value = barcode.rawValue;
          if (value != null && value.isNotEmpty) {
            onCode(value);
            return;
          }
        }
      },
      errorBuilder: (context, _) => onError(context),
    );
  }

  @override
  Future<void> resume() => _controller.start();

  @override
  Future<void> stop() => _controller.stop();

  @override
  Future<void> dispose() => _controller.dispose();
}

final scannerCameraFactoryProvider = Provider<ScannerCamera Function()>(
  (ref) => MobileScannerCamera.new,
);
