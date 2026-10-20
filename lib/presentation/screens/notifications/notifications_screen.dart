import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/inbox_layout.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/app_notification_model.dart';
import '../../../data/models/inbox_item.dart';
import '../../../data/services/announcement_route.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/notification/notification_provider.dart';
import '../../widgets/biso/biso.dart';
import 'inbox_widgets.dart';

/// In-app notification inbox: filter chips, pinned urgent rows, then the
/// rest grouped by day. Lists announcements addressed to the current user
/// (broadcast + targeted) and lets them open the linked content.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key, this.clock});

  /// Source of "now" for pinning, grouping and relative times. Tests inject
  /// a fixed clock.
  final DateTime Function()? clock;

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  InboxFilter _filter = InboxFilter.all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(notificationInboxProvider);

    return BisoPage(
      title: l10n.notificationsMessage,
      leading: BisoBackButton(
        onPressed: () => NavigationUtils.safeGoBack(context),
      ),
      onRefresh: () => ref.read(notificationInboxProvider.notifier).refresh(),
      slivers: _buildSlivers(context, l10n, state),
    );
  }

  List<Widget> _buildSlivers(
    BuildContext context,
    AppLocalizations l10n,
    NotificationInboxState state,
  ) {
    if (state.isLoading && state.items.isEmpty) {
      return const [SliverToBoxAdapter(child: BisoSkeleton.rows())];
    }

    if (state.error != null && state.items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: BisoErrorState(
            message: state.error,
            onRetry: () => ref.read(notificationInboxProvider.notifier).load(),
          ),
        ),
      ];
    }

    final empty = SliverFillRemaining(
      hasScrollBody: false,
      child: BisoEmptyState(
        icon: CupertinoIcons.bell,
        title: l10n.inboxEmptyTitle,
        message: l10n.inboxEmptyMessage,
      ),
    );
    if (state.items.isEmpty) return [empty];

    final now = (widget.clock ?? DateTime.now)();
    final filtered = applyFilter(state.items, _filter);
    final sections = groupByDay(filtered, now);
    // Urgent rows stay pinned under every filter: a filter must not hide
    // urgent information, so only the day groups are filtered.
    final grouped = {
      for (final s in groupByDay(state.items, now)) ...{
        for (final n in s.items) n.id,
      },
    };
    final pinned = [
      for (final n in pinUrgent(state.items, now))
        if (!grouped.contains(n.id)) n,
    ];

    return [
      SliverToBoxAdapter(
        child: _FilterChips(
          selected: _filter,
          onSelected: (f) => setState(() => _filter = f),
        ),
      ),
      if (filtered.isEmpty && pinned.isEmpty) empty,
      if (pinned.isNotEmpty)
        SliverToBoxAdapter(child: _group(context, null, pinned, now)),
      for (final section in sections)
        SliverToBoxAdapter(
          child: _group(
            context,
            _dayLabel(l10n, section.day),
            section.items,
            now,
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
  }

  Widget _group(
    BuildContext context,
    String? title,
    List<AppNotification> items,
    DateTime now,
  ) {
    final hasImage = items.any(
      (n) => !n.isUrgent && (n.image?.isNotEmpty ?? false),
    );
    return BisoSection(
      title: title,
      padding: EdgeInsets.fromLTRB(16, title == null ? 8 : 20, 16, 0),
      child: BisoListGroup(
        dividerIndent: hasImage ? kInboxThumbDividerIndent : 60,
        children: [
          for (final n in items)
            InboxRow(
              key: ValueKey(n.id),
              notification: n,
              now: now,
              onTap: () => _handleTap(context, n),
              onOpenItem: (item) => _openItem(context, n, item),
              onSeeAll: () => _openAnnouncement(context, n),
            ),
        ],
      ),
    );
  }

  String _dayLabel(AppLocalizations l10n, InboxDay day) => switch (day) {
    InboxDay.today => l10n.inboxDayToday,
    InboxDay.yesterday => l10n.inboxDayYesterday,
    InboxDay.thisWeek => l10n.inboxDayThisWeek,
    InboxDay.earlier => l10n.inboxDayEarlier,
  };

  // Every tap pushes inside the tab shell, where the inbox lives too, so Back
  // returns to the inbox.

  Future<void> _openItem(
    BuildContext context,
    AppNotification n,
    InboxItem item,
  ) async {
    await ref.read(notificationInboxProvider.notifier).markRead(n);
    if (context.mounted) context.push(item.route);
  }

  Future<void> _openAnnouncement(
    BuildContext context,
    AppNotification n,
  ) async {
    await ref.read(notificationInboxProvider.notifier).markRead(n);
    if (n.id.isNotEmpty && context.mounted) {
      context.push('/announcements/${Uri.encodeComponent(n.id)}');
    }
  }

  Future<void> _handleTap(BuildContext context, AppNotification n) async {
    await ref.read(notificationInboxProvider.notifier).markRead(n);
    final route = announcementRouteFor(n);
    if (route != null && context.mounted) context.push(route);
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelected});

  final InboxFilter selected;
  final ValueChanged<InboxFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    String label(InboxFilter f) => switch (f) {
      InboxFilter.all => l10n.all,
      InboxFilter.events => l10n.eventsMessage,
      InboxFilter.news => l10n.newsTitle,
      InboxFilter.jobs => l10n.inboxFilterJobs,
      InboxFilter.fromBiso => l10n.inboxFilterFromBiso,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          for (final f in InboxFilter.values) ...[
            ChoiceChip(
              label: Text(label(f)),
              selected: f == selected,
              showCheckmark: false,
              backgroundColor: palette.surface,
              selectedColor: palette.primary,
              side: BorderSide(color: palette.hairline),
              labelStyle: text.labelLarge?.copyWith(
                color: f == selected ? palette.onPrimary : palette.ink,
              ),
              onSelected: (_) => onSelected(f),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}
