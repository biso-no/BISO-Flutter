import '../../core/utils/app_version.dart';
import 'app_config.dart';
import 'update_policy.dart';

/// What the app should do about updates.
enum UpdatePrompt {
  /// Nothing to show.
  none,

  /// A dismissible nudge.
  recommended,

  /// A full block: the installed version is below the minimum.
  required,
}

/// How long a dismissed recommendation stays hidden.
const updateSnoozeDuration = Duration(days: 3);

/// The user dismissing the recommended-update nudge for [version].
///
/// It only hides that exact version: a higher recommended version is a new
/// reason to ask and resets the snooze.
class UpdateSnooze {
  const UpdateSnooze({required this.version, required this.dismissedAt});

  final String version;
  final DateTime dismissedAt;
}

/// Decides between no prompt, a nudge and a block.
///
/// Fails open everywhere: only a fresh [AppConfigSource.network] answer may
/// prompt, and an installed or server version we cannot parse means no
/// prompt. A `minimum` beats any snooze.
UpdatePrompt decideUpdate({
  required String installedVersion,
  required UpdatePolicy policy,
  required AppConfigSource source,
  required UpdateSnooze? snooze,
  required DateTime now,
}) {
  if (source != AppConfigSource.network) return UpdatePrompt.none;

  final installed = AppVersion.tryParse(installedVersion);
  if (installed == null) return UpdatePrompt.none;

  final minimum = AppVersion.tryParse(policy.minimum);
  if (minimum != null && installed < minimum) return UpdatePrompt.required;

  final recommended = AppVersion.tryParse(policy.recommended);
  if (recommended == null || !(installed < recommended)) {
    return UpdatePrompt.none;
  }

  final isSnoozed =
      snooze != null &&
      snooze.version == policy.recommended &&
      now.isBefore(snooze.dismissedAt.add(updateSnoozeDuration));
  return isSnoozed ? UpdatePrompt.none : UpdatePrompt.recommended;
}
