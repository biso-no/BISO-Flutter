import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Makes the screen easy to scan: awake and bright. [exit] undoes both.
abstract interface class ScreenPresentation {
  Future<void> enter();
  Future<void> exit();
}

/// Uses the app-level brightness, so the system setting is never changed.
class DeviceScreenPresentation implements ScreenPresentation {
  @override
  Future<void> enter() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // Unsupported device: the pass still shows.
    }
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(1.0);
    } catch (_) {
      // Unsupported device: the pass still shows.
    }
  }

  @override
  Future<void> exit() async {
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (_) {
      // Nothing to restore.
    }
    try {
      await WakelockPlus.disable();
    } catch (_) {
      // Nothing to restore.
    }
  }
}
