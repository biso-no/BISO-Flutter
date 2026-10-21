import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/update_decision.dart';
import '../../data/services/store_updater.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/config/update_prompt_provider.dart';
import 'notification_topics_prompt.dart';

/// What the student chose in the popup.
enum _Choice { update, notNow }

/// The dismissible nudge for [UpdatePrompt.recommended].
class _UpdateRecommendedDialog extends StatelessWidget {
  const _UpdateRecommendedDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.updateRecommendedTitle),
      content: Text(l10n.updateRecommendedBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_Choice.notNow),
          child: Text(l10n.updateNotNow),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_Choice.update),
          child: Text(l10n.updateButton),
        ),
      ],
    );
  }
}

/// Set while a popup is being decided on or displayed, so the rebuilds that
/// call [maybeShowUpdateRecommended] cannot stack a second one. Claimed
/// synchronously, before the first await.
bool _inFlight = false;

/// Whether the popup has been shown in this session.
bool _shownThisSession = false;

bool _showing = false;

/// Whether the update popup is on screen. The topics prompt does not open on
/// top of it.
bool get updateRecommendedShowing => _showing;

/// Forgets that the popup was shown, as a fresh launch would. For tests,
/// which share one isolate - and so this state - across every test in a file.
@visibleForTesting
void resetUpdateRecommendedSession() {
  _inFlight = false;
  _shownThisSession = false;
  _showing = false;
}

/// Shows the recommended-update popup, at most once per session.
///
/// Only while [updatePromptProvider] is [UpdatePrompt.recommended]: during a
/// block the required overlay is up instead. A topics prompt still checking
/// whether to show is waited for first, and once the topics sheet has been
/// shown in this session the popup stays away, so a student is not asked two
/// things in one session.
///
/// *Update* closes the popup and starts the store update. *Not now* — or any
/// other way of dismissing it — snoozes the recommendation.
///
/// Safe to call on every build, like `maybeShowTopicsPrompt`.
Future<void> maybeShowUpdateRecommended(
  BuildContext context,
  WidgetRef ref,
) async {
  if (_inFlight || _shownThisSession) return;
  if (ref.read(updatePromptProvider) != UpdatePrompt.recommended) return;
  _inFlight = true;
  try {
    await topicsPromptSettled();
    if (!context.mounted || topicsPromptShownThisSession) return;
    // The answer may have changed while the topics prompt was deciding.
    if (ref.read(updatePromptProvider) != UpdatePrompt.recommended) return;

    final prompt = ref.read(updatePromptProvider.notifier);
    final updater = ref.read(storeUpdaterProvider);
    _shownThisSession = true;
    _showing = true;
    final choice = await showDialog<_Choice>(
      context: context,
      builder: (_) => const _UpdateRecommendedDialog(),
    );
    _showing = false;

    if (choice == _Choice.update) {
      await updater.startUpdate();
    } else {
      await prompt.snooze();
    }
  } finally {
    _showing = false;
    _inFlight = false;
  }
}
