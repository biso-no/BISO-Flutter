import 'package:flutter/cupertino.dart';
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
    // Until auth is known the card would fetch anonymously and show "Sign in".
    if (ref.watch(authStateProvider.select((s) => s.isLoading))) {
      return const SizedBox.shrink();
    }
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

    // Tapping the chosen answer again takes it back.
    Future<void> onTap(EventRsvpStatus tapped) async {
      final messenger = ScaffoldMessenger.of(context);
      final result = await ref
          .read(eventRsvpProvider(event.id).notifier)
          .respond(summary.mine == tapped ? null : tapped);
      if (result != EventRsvpSaveResult.failed || !context.mounted) return;
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
            // Not disabled while saving: a disabled button loses its fill,
            // and the chosen answer must stay lit.
            IgnorePointer(
              ignoring: state.saving,
              child: _RsvpAnswers(mine: summary.mine, onTap: onTap),
            ),
          ] else if (!signedIn) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: _RsvpButton(
                icon: CupertinoIcons.person_crop_circle,
                label: l10n.eventRsvpSignIn,
                onPressed: () => context.go('/auth/login'),
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

/// The three answers. "Going" spans the row and the other two share the next
/// one, so "Kommer ikke" fits on one line instead of wrapping in a third of
/// it. With text too large for half a row, all three stack.
class _RsvpAnswers extends StatelessWidget {
  const _RsvpAnswers({required this.mine, required this.onTap});

  final EventRsvpStatus? mine;
  final ValueChanged<EventRsvpStatus> onTap;

  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    Widget answer(EventRsvpStatus status, IconData icon, String label) =>
        _RsvpButton(
          key: ValueKey('event-rsvp-${status.name}'),
          icon: icon,
          label: label,
          selected: mine == status,
          onPressed: () => onTap(status),
        );

    final going = answer(
      EventRsvpStatus.going,
      CupertinoIcons.checkmark_alt,
      l10n.eventRsvpGoing,
    );
    final maybe = answer(
      EventRsvpStatus.maybe,
      CupertinoIcons.question,
      l10n.eventRsvpMaybe,
    );
    final notGoing = answer(
      EventRsvpStatus.notGoing,
      CupertinoIcons.xmark,
      l10n.eventRsvpNotGoing,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final paired = _fitHalfRow(context, constraints.maxWidth, [
          l10n.eventRsvpMaybe,
          l10n.eventRsvpNotGoing,
        ]);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            going,
            const SizedBox(height: _gap),
            if (paired)
              Row(
                children: [
                  Expanded(child: maybe),
                  const SizedBox(width: _gap),
                  Expanded(child: notGoing),
                ],
              )
            else ...[
              maybe,
              const SizedBox(height: _gap),
              notGoing,
            ],
          ],
        );
      },
    );
  }

  /// Whether every label fits on one line in half of [width] at the reader's
  /// text size. At large accessibility sizes it doesn't, and a half-width
  /// button breaks "Kanskje" mid-word.
  static bool _fitHalfRow(
    BuildContext context,
    double width,
    List<String> labels,
  ) {
    final style = Theme.of(context).textTheme.labelLarge;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final room = (width - _gap) / 2 - _RsvpButton.chrome;
    return labels.every((label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final fits = painter.width <= room;
      painter.dispose();
      return fits;
    });
  }
}

/// One RSVP button: outlined in the primary colour, filled when [selected].
/// [selected] is null for the sign-in button, which is not an answer.
///
/// Not the theme's [OutlinedButton]: that one is borderless with a
/// `surfaceRaised` fill, all but the colour of the page behind the card, and
/// the first version's [SegmentedButton] marked the chosen answer with a tint
/// pale enough to read as disabled.
class _RsvpButton extends StatelessWidget {
  const _RsvpButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool? selected;

  // Narrower than the theme's padding, so "Kommer ikke" fits half a row.
  static const _padding = EdgeInsets.symmetric(horizontal: 12);
  static const _iconSize = 18.0;

  /// Width around the label: padding, icon, the icon's 8px gap, and border.
  static const chrome = 12 * 2 + _iconSize + 8 + 3;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final iconWidget = Icon(icon, size: _iconSize);
    final text = Text(label, textAlign: TextAlign.center);
    final button = selected ?? false
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: iconWidget,
            label: text,
            style: FilledButton.styleFrom(padding: _padding),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: iconWidget,
            label: text,
            style: OutlinedButton.styleFrom(
              backgroundColor: palette.surface,
              foregroundColor: palette.primary,
              side: BorderSide(color: palette.primary, width: 1.5),
              padding: _padding,
            ),
          );
    if (selected == null) return button;
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: button,
      ),
    );
  }
}
