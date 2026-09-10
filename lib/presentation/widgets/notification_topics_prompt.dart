import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/notification_topics.dart';
import '../../providers/auth/auth_provider.dart';
import '../../providers/notification/notification_provider.dart';

/// Asked once, the first time a student reaches the app signed in.
///
/// Covers both entry points identically: a new signup arrives here once
/// onboarding completes, and an existing Appwrite user arrives on their first
/// app login. There is deliberately only one of these — the previous design had
/// a second copy inside onboarding, and it silently discarded every choice.
class NotificationTopicsPrompt extends ConsumerStatefulWidget {
  const NotificationTopicsPrompt({super.key});

  @override
  ConsumerState<NotificationTopicsPrompt> createState() =>
      _NotificationTopicsPromptState();
}

/// The sheet's state machine.
///
/// The sheet is opened with `isDismissible: false, enableDrag: false` — a
/// student must resolve it, not brush past it — so every state that can be
/// reached must also offer a way out. [ready] is left by Continue, and every
/// other state offers "Skip for now" (see `_skip`): [loadFailed] and
/// [saveFailed] pair it with their error, so a persistent failure can never
/// strand the student, and [loading] offers it too, because nothing here times
/// out — a load that hangs rather than fails would otherwise leave the student
/// behind a spinner with no way forward. (A save that hangs once Continue is
/// pressed is still not covered, for the same lack of a timeout.)
enum _PromptStatus {
  /// The initial [NotificationService.loadTopicIntent] read is in flight.
  /// "Skip for now" is already offered, in case it never answers.
  loading,

  /// That read failed. Nothing has been shown or saved yet, so the only
  /// honest options are retrying it or skipping — never fabricated defaults,
  /// which risk being persisted over a migrated opt-out the instant the
  /// student taps Continue.
  loadFailed,

  /// Intent loaded successfully; the switches and Continue are live.
  ready,

  /// Continue was pressed and `saveTopicIntent` threw. The sheet stays open,
  /// with the switches exactly as the student left them, so Continue can
  /// retry — and Skip remains available in case the failure persists.
  saveFailed,
}

class _NotificationTopicsPromptState
    extends ConsumerState<NotificationTopicsPrompt> {
  Map<String, bool> _intent = Map<String, bool>.from(kDefaultTopicIntent);
  _PromptStatus _status = _PromptStatus.loading;

  /// True while a load or save attempt is in flight, so the switches and
  /// buttons can be disabled without needing a fifth [_PromptStatus].
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadIntent();
  }

  /// Seed the switches from whatever this student has already chosen —
  /// including a legacy `topic_subscriptions` map, migrated by
  /// [NotificationService.loadTopicIntent] — instead of always starting from
  /// [kDefaultTopicIntent]. Without this, a student with existing preferences
  /// would see every switch reset to the defaults the first time this sheet
  /// (now actually) shows for them.
  ///
  /// A failed read no longer falls back to [kDefaultTopicIntent]: showing
  /// fabricated defaults and then letting the student tap Continue would
  /// persist those defaults over their real migrated intent — the exact
  /// data-loss this prompt exists to avoid. Instead it reports [loadFailed],
  /// which offers a retry and a skip (see [_PromptStatus.loadFailed]).
  Future<void> _loadIntent() async {
    final service = ref.read(notificationServiceProvider);
    try {
      final intent = await service.loadTopicIntent();
      if (!mounted) return;
      setState(() {
        _intent = intent;
        _status = _PromptStatus.ready;
      });
    } catch (e) {
      debugPrint('NotificationTopicsPrompt: could not load intent: $e');
      if (!mounted) return;
      setState(() => _status = _PromptStatus.loadFailed);
    }
  }

  /// Re-runs [_loadIntent] from the "Try again" button on [_PromptStatus.loadFailed].
  ///
  /// Distinct from [_loadIntent] itself so the initial call from [initState]
  /// never calls [setState] before its first `await` — [_status] already
  /// defaults to [_PromptStatus.loading], so nothing needs setting there.
  void _retryLoad() {
    setState(() {
      _status = _PromptStatus.loading;
      _busy = false;
    });
    _loadIntent();
  }

  /// Closes the sheet without saving anything, and keeps it closed for this
  /// student for the rest of this session.
  ///
  /// The "answered" marker ([NotificationService.hasAnsweredTopicPrompt]) is
  /// only ever written by a successful [NotificationService.saveTopicIntent]
  /// call, so skipping leaves it unset and the student is asked again on the
  /// next launch. Not before then: `BisoApp.build` calls
  /// [maybeShowTopicsPrompt] on every rebuild, which would bring the sheet
  /// straight back, so the sheet closes with `true` and the call that opened
  /// it records the skip for its student (see [_studentsWhoSkipped]).
  ///
  /// This is the prompt's only escape hatch when loading hangs or fails, or
  /// saving keeps failing — the sheet itself is deliberately non-dismissible
  /// and non-draggable (see [_PromptStatus]).
  void _skip() {
    Navigator.of(context).pop(true);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final service = ref.read(notificationServiceProvider);

    // Intent first, and regardless of what the OS dialog returns: declining the
    // system prompt is not the same as wanting nothing, and this choice should
    // take effect if they enable notifications later.
    try {
      await service.saveTopicIntent(_intent);
    } catch (e) {
      debugPrint('NotificationTopicsPrompt: could not save intent: $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _status = _PromptStatus.saveFailed;
        });
      }
      // Stop here: nothing was recorded, so there is nothing to reconcile,
      // and the sheet must stay open (see _PromptStatus.saveFailed) rather
      // than close as if the student's choice had been saved.
      return;
    }

    // The intent is genuinely stored from here on, so nothing below may
    // prevent the sheet from closing: the sheet closes whatever happens next.
    // The launch reconciler retries on the next start, whereas leaving the
    // sheet open on a throw here would strand the student behind a sheet
    // that is deliberately non-dismissible, with no way out but killing the
    // app.
    try {
      await service.requestPermission();
      final campusId = ref.read(authStateProvider).user?.campusId;
      await service.reconcile(campusId: campusId);
    } catch (e) {
      debugPrint('NotificationTopicsPrompt: could not subscribe now: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Stay in the loop',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.strongBlue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pick what you want to hear about. You will get updates for your '
              'campus and anything BISO publishes nationally.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ..._buildBody(theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBody(ThemeData theme) {
    switch (_status) {
      case _PromptStatus.loading:
        return [
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          TextButton(onPressed: _skip, child: const Text('Skip for now')),
        ];

      case _PromptStatus.loadFailed:
        return [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Could not load your notification settings.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
          FilledButton(
            onPressed: _busy ? null : _retryLoad,
            child: const Text('Try again'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : _skip,
            child: const Text('Skip for now'),
          ),
        ];

      case _PromptStatus.ready:
      case _PromptStatus.saveFailed:
        final saveFailed = _status == _PromptStatus.saveFailed;
        return [
          if (saveFailed) ...[
            Text(
              'Could not save your choices. Check your connection and try '
              'again.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 12),
          ],
          for (final topic in NotificationTopic.values)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(topic.label),
              value: _intent[topic.id] ?? false,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _intent[topic.id] = value),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Continue'),
          ),
          if (saveFailed) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _skip,
              child: const Text('Skip for now'),
            ),
          ],
        ];
    }
  }
}

/// True while a prompt is being decided on or displayed.
///
/// `BisoApp` rebuilds whenever the launch reconciler transitions, which happens
/// on the same auth change that makes the prompt eligible and again when the
/// network work finishes — routinely while the sheet is still open. The stored
/// marker is not written until the student taps Continue, so it cannot prevent
/// a second, stacked, non-dismissible sheet on its own. This flag is claimed
/// synchronously, before the first await, so two rebuilds in one turn cannot
/// both get past it.
bool _promptInFlight = false;

/// The students, by user id, who have skipped the prompt in this session.
///
/// Skipping deliberately writes no marker, and `BisoApp` keeps rebuilding
/// after the sheet closes — the launch reconciler alone transitions moments
/// later — each time calling [maybeShowTopicsPrompt], which would show the
/// sheet again straight away. Held in memory only, so the next launch asks
/// again.
///
/// Per student, because whether the prompt has been answered is stored per
/// account. A single flag for the session silenced the prompt for anyone who
/// signed in on this device after a skip, until the next launch.
final Set<String?> _studentsWhoSkipped = <String?>{};

/// Forgets every skip, as a fresh launch would. For tests, which share one
/// isolate - and so this set - across every test in a file.
@visibleForTesting
void resetTopicsPromptSession() => _studentsWhoSkipped.clear();

/// Show the prompt if this student has not answered it yet, and has not
/// skipped it this session.
///
/// Safe to call on every build — it checks the skip, the in-flight flag and
/// the stored marker, and does nothing for anyone who has already chosen.
Future<void> maybeShowTopicsPrompt(BuildContext context, WidgetRef ref) async {
  final studentId = ref.read(currentUserProvider)?.id;
  if (_studentsWhoSkipped.contains(studentId)) return;
  if (_promptInFlight) return;
  _promptInFlight = true;
  try {
    await _showTopicsPrompt(context, ref, studentId);
  } finally {
    _promptInFlight = false;
  }
}

/// [studentId] is who the prompt is being shown for, read before anything is
/// awaited, so a skip is recorded for the student who was actually asked.
Future<void> _showTopicsPrompt(
  BuildContext context,
  WidgetRef ref,
  String? studentId,
) async {
  final service = ref.read(notificationServiceProvider);
  if (await service.hasAnsweredTopicPrompt()) return;
  if (!context.mounted) return;

  final skipped = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => const NotificationTopicsPrompt(),
  );
  if (skipped == true) _studentsWhoSkipped.add(studentId);
}
