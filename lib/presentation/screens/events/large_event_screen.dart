import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/large_event_model.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../../providers/large_event/large_event_items_provider.dart';
import '../../widgets/biso/biso.dart';

class LargeEventScreen extends ConsumerWidget {
  final LargeEventModel event;
  const LargeEventScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campus = ref.watch(filterCampusProvider);
    final cfg = event.campusConfig(campus.id);

    return BisoPage(
      overImage: true,
      title: event.name,
      largeTitle: false,
      leading: BisoBackButton(
        onPressed: () =>
            NavigationUtils.safeGoBack(context, fallbackRoute: '/explore'),
      ),
      slivers: [
        SliverToBoxAdapter(child: _EventHero(event: event)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _EventSummary(event: event),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _DatePills(
              from: event.startDate,
              to: event.endDate,
              color: event.primaryColor,
            ),
          ),
        ),
        if (cfg != null) SliverToBoxAdapter(child: _TicketingSection(cfg: cfg)),

        // Prefer subevents from collection; fallback to embedded schedule
        SliverToBoxAdapter(
          child: Consumer(
            builder: (context, ref, _) {
              final state = ref.watch(
                largeEventItemsProvider((
                  eventId: event.id,
                  campusId: campus.id,
                )),
              );
              final hasItems = state.items.isNotEmpty;
              final items = hasItems ? state.items : (cfg?.schedule ?? []);
              if (items.isEmpty) return const SizedBox.shrink();
              return _ScheduleList(items: items);
            },
          ),
        ),
      ],
    );
  }
}

/// The hero band at the top of the page: `event.backgroundImageUrl` (or a
/// `palette.primary` block when there is none) behind a scrim and the event
/// name, matching `CampusCover`'s over-image pattern.
class _EventHero extends StatelessWidget {
  final LargeEventModel event;
  const _EventHero({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    final imageUrl = event.backgroundImageUrl;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return SizedBox(
      key: const ValueKey('large-event-hero'),
      height: 360,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasImage)
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              memCacheWidth: 1200,
              errorWidget: (_, _, _) => ColoredBox(color: palette.primary),
            )
          else
            ColoredBox(color: palette.primary),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.45),
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Text(
              event.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.displaySmall?.copyWith(
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The event logo (if any) beside its description.
class _EventSummary extends StatelessWidget {
  final LargeEventModel event;
  const _EventSummary({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    final description = Text(
      event.description,
      style: theme.textTheme.bodyLarge?.copyWith(color: palette.muted),
    );

    final logoUrl = event.logoUrl;
    if (logoUrl == null || logoUrl.isEmpty) return description;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.hairline),
          ),
          child: CachedNetworkImage(
            imageUrl: logoUrl,
            fit: BoxFit.contain,
            memCacheWidth: 128,
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: description),
      ],
    );
  }
}

class _DatePills extends StatelessWidget {
  final DateTime from;
  final DateTime to;
  final Color color;
  const _DatePills({
    required this.from,
    required this.to,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600);
    // A Wrap rather than a strict Row: at large text scales the two date
    // pills flow onto another line instead of overflowing the page width.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text('${from.day}.${from.month}.${from.year}', style: style),
        ),
        Icon(CupertinoIcons.arrow_right, size: 16, color: palette.muted),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text('${to.day}.${to.month}.${to.year}', style: style),
        ),
      ],
    );
  }
}

class _TicketingSection extends StatelessWidget {
  final LargeEventCampusConfig cfg;
  const _TicketingSection({required this.cfg});

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final theme = Theme.of(context);
    switch (cfg.ticketingModel) {
      case LargeEventTicketingModel.allAccess:
        final rows = <Widget>[
          if (cfg.allAccessPassUrl != null)
            BisoListRow(
              title: 'Buy Pass',
              leading: const BisoIconTile(
                icon: CupertinoIcons.ticket_fill,
                accent: BisoAccent.gold,
              ),
              onTap: () => launchUrl(Uri.parse(cfg.allAccessPassUrl!)),
            ),
          if (cfg.ticketPortalUrl != null)
            BisoListRow(
              title: 'Open Ticket Portal',
              leading: const BisoIconTile(
                icon: CupertinoIcons.ticket_fill,
                accent: BisoAccent.gold,
              ),
              onTap: () => launchUrl(Uri.parse(cfg.ticketPortalUrl!)),
            ),
        ];
        return BisoSection(
          title: 'All-Access Pass',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'One ticket grants access to all events on this campus.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.muted,
                ),
              ),
              if (rows.isNotEmpty) ...[
                const SizedBox(height: 12),
                BisoListGroup(children: rows),
              ],
            ],
          ),
        );
      case LargeEventTicketingModel.perEvent:
        if (cfg.schedule.isEmpty) return const SizedBox.shrink();
        final rows = <Widget>[
          for (final item in cfg.schedule) ...[
            BisoListRow(
              title: item.title,
              subtitle: _formatScheduleSubtitle(item),
              leading: const BisoIconTile(
                icon: CupertinoIcons.calendar,
                accent: BisoAccent.blue,
              ),
            ),
            if (item.ticketUrl != null)
              BisoListRow(
                title: 'Tickets',
                leading: const BisoIconTile(
                  icon: CupertinoIcons.ticket_fill,
                  accent: BisoAccent.gold,
                ),
                onTap: () => launchUrl(Uri.parse(item.ticketUrl!)),
              ),
          ],
        ];
        return BisoSection(
          title: 'Events & Tickets',
          child: BisoListGroup(children: rows),
        );
    }
  }

  String _formatScheduleSubtitle(LargeEventScheduleItem item) {
    final start = item.startTime;
    final end = item.endTime;
    final date = '${start.day}.${start.month}.${start.year}';
    final time = end != null
        ? '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} - ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}'
        : '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    final loc = item.location != null ? ' • ${item.location}' : '';
    return '$date • $time$loc';
  }
}

class _ScheduleList extends StatelessWidget {
  final List<LargeEventScheduleItem> items;
  const _ScheduleList({required this.items});

  @override
  Widget build(BuildContext context) {
    return BisoSection(
      title: 'Schedule',
      child: BisoListGroup(
        children: [
          for (final item in items)
            BisoListRow(
              title: item.title,
              subtitle: item.subtitle,
              leading: const BisoIconTile(
                icon: CupertinoIcons.calendar,
                accent: BisoAccent.blue,
              ),
            ),
        ],
      ),
    );
  }
}
