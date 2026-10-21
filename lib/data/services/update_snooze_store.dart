import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/update_decision.dart';

/// Device-local record of the last recommended update the user dismissed.
///
/// One snooze at a time: dismissing a recommendation replaces whatever was
/// dismissed before, and it only ever hides that one version (see
/// [decideUpdate]). It lives on the device because the nudge does: a student
/// who dismissed it on their phone has not dismissed it on their tablet.
class UpdateSnoozeStore {
  static const String _versionKey = 'update_snooze_version';
  static const String _dismissedAtKey = 'update_snooze_at';

  /// The stored snooze, or `null` when there is none.
  ///
  /// A half-written or unreadable snooze reads as none rather than throwing.
  /// The worst that does is show a nudge again; an exception here would stop
  /// the app from ever deciding about updates.
  Future<UpdateSnooze?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final version = prefs.getString(_versionKey);
      final dismissedAt = prefs.getInt(_dismissedAtKey);
      if (version == null || version.isEmpty || dismissedAt == null) {
        return null;
      }
      return UpdateSnooze(
        version: version,
        dismissedAt: DateTime.fromMillisecondsSinceEpoch(dismissedAt),
      );
    } catch (e) {
      debugPrint('UpdateSnoozeStore: unreadable snooze: $e');
      return null;
    }
  }

  Future<void> write(UpdateSnooze snooze) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_versionKey, snooze.version),
      prefs.setInt(_dismissedAtKey, snooze.dismissedAt.millisecondsSinceEpoch),
    ]);
  }
}
