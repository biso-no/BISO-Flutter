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

class _NotificationTopicsPromptState
    extends ConsumerState<NotificationTopicsPrompt> {
  late final Map<String, bool> _intent = Map<String, bool>.from(
    kDefaultTopicIntent,
  );
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final service = ref.read(notificationServiceProvider);
    final campusId = ref.read(authStateProvider).user?.campusId;

    // Intent first, and regardless of what the OS dialog returns: declining the
    // system prompt is not the same as wanting nothing, and this choice should
    // take effect if they enable notifications later.
    try {
      await service.saveTopicIntent(_intent);
    } catch (e) {
      debugPrint('NotificationTopicsPrompt: could not save intent: $e');
    }

    await service.requestPermission();
    await service.reconcile(campusId: campusId);

    if (mounted) Navigator.of(context).pop();
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
            for (final topic in NotificationTopic.values)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(topic.label),
                value: _intent[topic.id] ?? false,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _intent[topic.id] = value),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Show the prompt if this student has not answered it yet.
///
/// Safe to call on every build — it checks the stored marker first and does
/// nothing for anyone who has already chosen.
Future<void> maybeShowTopicsPrompt(BuildContext context, WidgetRef ref) async {
  final service = ref.read(notificationServiceProvider);
  if (await service.hasAnsweredTopicPrompt()) return;
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => const NotificationTopicsPrompt(),
  );
}
