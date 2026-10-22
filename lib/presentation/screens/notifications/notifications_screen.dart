import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/inbox_layout.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/app_notification_model.dart';
import '../../../data/models/inbox_item.dart';
import '../../../data/services/announcement_route.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/notification/inbox_opened_items_provider.dart';
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
    // "Clear all" clears exactly what the student can see under this filter.
    final onScreen = [
      ...pinned,
      for (final section in sections) ...section.items,
    ];

    return [
      SliverToBoxAdapter(
        child: _FilterChips(
          selected: _filter,
          onSelected: (f) => setState(() => _filter = f),
          onClearAll: onScreen.isEmpty || state.isLoading
              ? null
              : () => _confirmClearAll(context, onScreen),
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
    final opened = ref.watch(inboxOpenedItemsProvider);
    return BisoSection(
      title: title,
      padding: EdgeInsets.fromLTRB(16, title == null ? 8 : 20, 16, 0),
      child: BisoListGroup(
        dividerIndent: hasImage ? kInboxThumbDividerIndent : 60,
        children: [
          for (final n in items)
            Dismissible(
              key: ValueKey('clear-${n.id}'),
              direction: DismissDirection.endToStart,
              background: const InboxClearBackground(),
              onDismissed: (_) => _clear([n.id]),
              // Swiping is out of reach for VoiceOver and TalkBack.
              child: Semantics(
                customSemanticsActions: {
                  CustomSemanticsAction(
                    label: AppLocalizations.of(context)!.inboxClear,
                  ): () =>
                      _clear([n.id]),
                },
                child: InboxRow(
                  notification: n,
                  now: now,
                  openedItemIds: opened.openedFor(n.id),
                  onTap: () => _handleTap(context, n),
                  onOpenItem: (item) => _openItem(context, n, item),
                  onSeeAll: () => _openAnnouncement(context, n),
                ),
              ),
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

  // Every tap marks the notification read and pushes inside the tab shell,
  // where the inbox lives too, so Back returns to the inbox. The marks update
  // the inbox at once and are not waited for: marking read goes to the
  // server, and the screen opens without that delay.

  void _openItem(BuildContext context, AppNotification n, InboxItem item) {
    // An opened card leaves the burst's strip.
    unawaited(
      ref.read(inboxOpenedItemsProvider.notifier).markOpened(n.id, item.id),
    );
    unawaited(ref.read(notificationInboxProvider.notifier).markRead(n));
    context.push(item.route);
  }

  void _openAnnouncement(BuildContext context, AppNotification n) {
    unawaited(ref.read(notificationInboxProvider.notifier).markRead(n));
    if (n.id.isNotEmpty) {
      context.push('/announcements/${Uri.encodeComponent(n.id)}');
    }
  }

  void _handleTap(BuildContext context, AppNotification n) {
    unawaited(ref.read(notificationInboxProvider.notifier).markRead(n));
    final route = announcementRouteFor(n);
    if (route != null) context.push(route);
  }

  /// Asks before clearing [rows], since clearing cannot be undone.
  void _confirmClearAll(BuildContext context, List<AppNotification> rows) {
    final l10n = AppLocalizations.of(context)!;
    final ids = [for (final n in rows) n.id];
    showBisoSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: BisoListGroup(
            children: [
              BisoListRow(
                title: l10n.inboxClearConfirmTitle(rows.length),
                subtitle: l10n.inboxClearConfirmMessage,
                showChevron: false,
              ),
              BisoListRow(
                leading: const BisoIconTile(
                  icon: CupertinoIcons.trash,
                  accent: BisoAccent.coral,
                ),
                title: l10n.inboxClear,
                destructive: true,
                showChevron: false,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _clear(ids);
                },
              ),
              BisoListRow(
                leading: const BisoIconTile(icon: CupertinoIcons.xmark),
                title: l10n.cancel,
                showChevron: false,
                onTap: () => Navigator.of(sheetContext).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Clears [ids], and tells the student when some of them came back.
  Future<void> _clear(List<String> ids) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final cleared = await ref
        .read(notificationInboxProvider.notifier)
        .clear(ids);
    if (!cleared && mounted) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.inboxClearFailed)));
    }
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.selected,
    required this.onSelected,
    this.onClearAll,
  });

  final InboxFilter selected;
  final ValueChanged<InboxFilter> onSelected;

  /// Shows the "Clear all" link after the chips when set.
  final VoidCallback? onClearAll;

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
    final clearAll = onClearAll;
    final chips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(16, 4, clearAll == null ? 16 : 0, 4),
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
    if (clearAll == null) return chips;

    // Outside the scroll view, so it stays in reach however far the chips
    // have scrolled.
    return Row(
      children: [
        Expanded(child: chips),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextButton(
            onPressed: clearAll,
            style: TextButton.styleFrom(
              foregroundColor: palette.link,
              minimumSize: const Size(44, 44),
              textStyle: text.labelLarge,
            ),
            child: Text(l10n.inboxClearAll),
          ),
        ),
      ],
    );
  }
}
