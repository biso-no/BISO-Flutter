import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/event_model.dart';
import '../../../data/models/event_rsvp.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/events/event_rsvp_provider.dart';
import '../../../providers/membership/membership_overview_provider.dart';
import '../biso/biso.dart';
import 'event_detail_body.dart' show eventTicketUri;

/// "Are you going?" on the event screen: Going / Maybe / Not going, and how
/// many are going. Renders nothing (not even a gap) when the event is over,
/// when answers are closed, or while the numbers are not available.
class EventRsvpCard extends ConsumerWidget {
  const EventRsvpCard({super.key, required this.event});

  final EventModel event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (event.isCompleted || event.isCancelled) return const SizedBox.shrink();
    final state = ref.watch(eventRsvpProvider(event.id));
    final summary = state.summary;
    if (summary == null || !summary.open) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    final l10n = AppLocalizations.of(context)!;
    final signedIn =
        ref.watch(authStateProvider.select((s) => s.signedInUserId)) != null;
    final blockedAsNonMember =
        event.memberOnly && !ref.watch(hasValidMembershipProvider);

    final counts = [
      if (summary.going > 0) l10n.eventRsvpGoingCount(summary.going),
      if (summary.maybe > 0) l10n.eventRsvpMaybeCount(summary.maybe),
    ].join(' · ');

    Future<void> onChanged(Set<EventRsvpStatus> picked) async {
      final messenger = ScaffoldMessenger.of(context);
      final saved = await ref
          .read(eventRsvpProvider(event.id).notifier)
          .respond(picked.isEmpty ? null : picked.first);
      if (saved || !context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.eventRsvpSaveFailed)));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.eventRsvpTitle,
            style: theme.textTheme.titleMedium?.copyWith(color: palette.ink),
          ),
          if (signedIn && !blockedAsNonMember) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<EventRsvpStatus>(
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: EventRsvpStatus.going,
                    label: Text(l10n.eventRsvpGoing),
                  ),
                  ButtonSegment(
                    value: EventRsvpStatus.maybe,
                    label: Text(l10n.eventRsvpMaybe),
                  ),
                  ButtonSegment(
                    value: EventRsvpStatus.notGoing,
                    label: Text(l10n.eventRsvpNotGoing),
                  ),
                ],
                selected: {?summary.mine},
                onSelectionChanged: state.saving ? null : onChanged,
              ),
            ),
          ] else if (!signedIn) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => context.go('/auth/login'),
                child: Text(l10n.eventRsvpSignIn),
              ),
            ),
          ],
          if (counts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              counts,
              style: theme.textTheme.bodyMedium?.copyWith(color: palette.muted),
            ),
          ],
          if (eventTicketUri(event) != null) ...[
            const SizedBox(height: 4),
            Text(
              l10n.eventRsvpTicketHint,
              style: theme.textTheme.bodySmall?.copyWith(color: palette.muted),
            ),
          ],
        ],
      ),
    );
  }
}
