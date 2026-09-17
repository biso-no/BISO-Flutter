import 'package:flutter/painting.dart';

import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/member_pass/scan_display.dart';

/// Fixed colors for the member pass and the scanner. They carry meaning
/// (a valid scan is green in any theme), so they stay outside BisoPalette.
abstract final class PassColors {
  static const card = Color(0xFF0B1F3A);
  static const cardInk = Color(0xFFFFFFFF);
  static const cardMuted = Color(0xB3FFFFFF);
  static const qrBackground = Color(0xFFFFFFFF);
  static const liveDot = Color(0xFF30D158);
  static const scannerBackground = Color(0xFF000000);

  /// The band's colors. The last repeats the first so the loop is seamless.
  static const holographic = [
    Color(0xFF7FDBFF),
    Color(0xFFB28DFF),
    Color(0xFFFF9EC7),
    Color(0xFFFFE08A),
    Color(0xFF8CF5C8),
    Color(0xFF7FDBFF),
  ];

  static Color scanTone(ScanTone tone) => switch (tone) {
    ScanTone.green => const Color(0xFF1E9E4A),
    ScanTone.orange => const Color(0xFFF07C00),
    ScanTone.amber => const Color(0xFFE0A800),
    ScanTone.red => const Color(0xFFD7263D),
    ScanTone.grey => const Color(0xFF5B6270),
  };

  /// Dark ink on light backgrounds, white otherwise.
  static Color inkOn(Color background) => background.computeLuminance() > 0.4
      ? const Color(0xFF111111)
      : const Color(0xFFFFFFFF);
}

String dayColorName(AppLocalizations l10n, String name) => switch (name) {
  'red' => l10n.dayColorRed,
  'orange' => l10n.dayColorOrange,
  'yellow' => l10n.dayColorYellow,
  'lime' => l10n.dayColorLime,
  'green' => l10n.dayColorGreen,
  'teal' => l10n.dayColorTeal,
  'cyan' => l10n.dayColorCyan,
  'blue' => l10n.dayColorBlue,
  'indigo' => l10n.dayColorIndigo,
  'purple' => l10n.dayColorPurple,
  'pink' => l10n.dayColorPink,
  'brown' => l10n.dayColorBrown,
  _ => name,
};

String scanMessageText(AppLocalizations l10n, ScannerResult result) =>
    switch (result.message) {
      ScanMessage.valid => l10n.scannerValid,
      ScanMessage.duplicate => _duplicate(
        l10n,
        result.secondsSincePrevious ?? 0,
      ),
      ScanMessage.checkId => l10n.scannerCheckId,
      ScanMessage.badCode => l10n.scannerBadCode,
      ScanMessage.stale => l10n.scannerStale,
      ScanMessage.expired => l10n.scannerExpired,
      ScanMessage.notMember => l10n.scannerNotMember,
      ScanMessage.notLinked => l10n.scannerNotLinked,
      ScanMessage.notValid => l10n.scannerNotValid,
      ScanMessage.unavailable => l10n.scannerUnavailable,
      ScanMessage.rateLimited => l10n.scannerRateLimited,
    };

String _duplicate(AppLocalizations l10n, int seconds) => seconds < 60
    ? l10n.scannerDuplicateSeconds(seconds)
    : l10n.scannerDuplicateMinutes(seconds ~/ 60);
