import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/models/event_model.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/membership/membership_overview_provider.dart';
import '../../../providers/ui/locale_provider.dart';
import '../biso/biso.dart';
import '../premium/premium_html_renderer.dart';
import 'your_trip_card.dart';

/// What the status badge actually communicates to a reader.
///
/// Derived from the event's dates, NOT from the Appwrite `status` column:
/// `status` is the editorial enum `draft`/`published`/`cancelled`, and every
/// row that reaches the app is `published` (see
/// `EventService.buildEventQueries`), so a status-derived badge would print
/// the constant string "published". `cancelled` is a real enum value and is
/// still honoured.
enum EventLifecycle { cancelled, upcoming, ongoing, completed }

EventLifecycle eventLifecycleOf(EventModel event) {
  if (event.isCancelled) return EventLifecycle.cancelled;
  if (event.isOngoing) return EventLifecycle.ongoing;
  if (event.isCompleted) return EventLifecycle.completed;
  return EventLifecycle.upcoming;
}

String eventLifecycleLabel(EventLifecycle lifecycle, AppLocalizations l10n) {
  switch (lifecycle) {
    case EventLifecycle.cancelled:
      return l10n.cancelledMessage;
    case EventLifecycle.ongoing:
      return l10n.liveMessage;
    case EventLifecycle.completed:
      return l10n.endedMessage;
    case EventLifecycle.upcoming:
      return l10n.upcomingMessage;
  }
}

/// One color per lifecycle, shared by the card and the detail body.
Color eventStatusColor(EventLifecycle lifecycle, BisoPalette palette) {
  switch (lifecycle) {
    case EventLifecycle.upcoming:
      return palette.link;
    case EventLifecycle.completed:
      // Past, inactive — not the active/selected meaning `link` carries.
      return palette.muted;
    case EventLifecycle.ongoing:
      return palette.success;
    case EventLifecycle.cancelled:
      return palette.error;
  }
}

/// The price line for an event, or null when there is nothing to charge.
///
/// The member price is shown to everyone: it is what membership gets you.
/// Tickets are sold by a third party, which is what applies it.
String? eventPriceLabel(EventModel event) {
  String nok(double amount) => 'NOK ${amount.toStringAsFixed(0)}';
  final price = event.price != null && event.price! > 0 ? event.price : null;
  final member = event.memberPrice;
  if (price == null) {
    return member != null && member > 0 ? 'Members ${nok(member)}' : null;
  }
  if (member != null && member < price) {
    return '${nok(price)} · Members ${nok(member)}';
  }
  return nok(price);
}

/// A small rounded label: lifecycle, category, tag.
class EventChip extends StatelessWidget {
  const EventChip({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: foreground),
    ),
  );
}

/// The event's ticket page, when it has a usable one.
Uri? eventTicketUri(EventModel event) {
  final raw = event.ticketUrl?.trim() ?? '';
  if (raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  return uri;
}

/// The content of one event: when, where, price, tickets, the description.
///
/// Sliver-free on purpose, so a screen can place it in any scroll view.
class EventDetailBody extends ConsumerWidget {
  const EventDetailBody({super.key, required this.event});

  final EventModel event;

  String _formatEventDate(DateTime startDate, DateTime? endDate, String lang) {
    // Appwrite's start_date/end_date parse as UTC DateTimes (isUtc == true).
    // Convert to the device's local time zone before formatting — and
    // before the same-day comparison below, so a start/end pair that spans
    // midnight only in UTC (or only locally) is judged by the calendar day
    // actually shown to the user. This is display-only: it must not be
    // backported to any comparison that decides event lifecycle/filtering.
    final localStart = startDate.toLocal();
    final localEnd = endDate?.toLocal();
    final formattedStartDate = DateFormat(
      'EEEE, MMM dd, yyyy • HH:mm',
      lang,
    ).format(localStart);
    if (localEnd != null &&
        localStart.day == localEnd.day &&
        localStart.month == localEnd.month &&
        localStart.year == localEnd.year) {
      return '$formattedStartDate - ${DateFormat('HH:mm', lang).format(localEnd)}';
    }
    return formattedStartDate;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    final l10n = AppLocalizations.of(context)!;
    final lang = ref.watch(localeProvider).languageCode;
    final lifecycle = eventLifecycleOf(event);
    final statusColor = eventStatusColor(lifecycle, palette);
    final price = eventPriceLabel(event);
    final contactName = event.contactName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          event.title,
          style: theme.textTheme.headlineSmall?.copyWith(color: palette.ink),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(CupertinoIcons.calendar, size: 20, color: palette.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _formatEventDate(event.startDate, event.endDate, lang),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.muted,
                ),
              ),
            ),
          ],
        ),
        if (event.location != null && event.location!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                CupertinoIcons.location_solid,
                size: 20,
                color: palette.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  event.location!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.muted,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            EventChip(
              label: eventLifecycleLabel(lifecycle, l10n),
              foreground: statusColor,
              background: statusColor.withValues(alpha: 0.12),
            ),
            if (event.memberOnly) const BisoMembersBadge(),
          ],
        ),
        if (price != null) ...[
          const SizedBox(height: 16),
          Text(
            price,
            style: theme.textTheme.titleMedium?.copyWith(color: palette.ink),
          ),
        ],
        if (eventTicketUri(event) case final ticketUri?
            when event.canRegister && !event.isCancelled) ...[
          const SizedBox(height: 16),
          _TicketButton(
            ticketUri: ticketUri,
            blockedAsNonMember:
                event.memberOnly && !ref.watch(hasValidMembershipProvider),
          ),
        ],
        const SizedBox(height: 24),
        // Personalized "Your trip" logistics for the signed-in user.
        // Renders nothing when signed out or with no assigned segments.
        YourTripCard(eventId: event.id),
        if (event.description.isNotEmpty) ...[
          Text(
            l10n.descriptionMessage,
            style: theme.textTheme.titleMedium?.copyWith(color: palette.ink),
          ),
          const SizedBox(height: 8),
          // `content_translations.description` is HTML — render it,
          // don't print the tags. Same helper jobs_screen uses.
          event.description.toFullHtml(
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.5,
              color: palette.muted,
            ),
            fontSize: 16,
          ),
          const SizedBox(height: 24),
        ],
        if (contactName != null && contactName.isNotEmpty)
          Text(
            l10n.eventOrganizedBy(contactName),
            style: theme.textTheme.bodyMedium?.copyWith(color: palette.muted),
          ),
      ],
    );
  }
}

/// Opens the third-party ticket page.
///
/// A members-only event is refused to non-members here, the same rule the
/// shop applies. It is presentation only: the ticket seller is what actually
/// sells the ticket, and it is where the member price is applied.
class _TicketButton extends StatelessWidget {
  const _TicketButton({
    required this.ticketUri,
    required this.blockedAsNonMember,
  });

  final Uri ticketUri;
  final bool blockedAsNonMember;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: blockedAsNonMember
              ? null
              : () =>
                    launchUrl(ticketUri, mode: LaunchMode.externalApplication),
          icon: Icon(
            blockedAsNonMember ? CupertinoIcons.lock : CupertinoIcons.tickets,
          ),
          label: Text(blockedAsNonMember ? 'Members only' : 'Get tickets'),
        ),
        if (blockedAsNonMember) ...[
          const SizedBox(height: 8),
          Text(
            'This event is for BISO members. If you are a member, check your '
            'membership under Profile → Membership.',
            style: theme.textTheme.bodySmall?.copyWith(color: palette.muted),
          ),
        ],
      ],
    );
  }
}
