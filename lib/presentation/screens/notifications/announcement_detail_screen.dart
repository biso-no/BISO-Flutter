import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/app_notification_model.dart';
import '../../../data/services/deep_link_service.dart';
import '../../../providers/notification/notification_provider.dart';
import '../../widgets/biso/biso.dart';
import '../../widgets/premium/premium_html_renderer.dart';
import '../../../generated/l10n/app_localizations.dart';
import 'inbox_widgets.dart';

/// Rich detail view for a single announcement.
///
/// Renders the announcement's HTML body (falling back to plain text) and marks
/// it read once on load so the inbox list and unread badge stay in sync.
class AnnouncementDetailScreen extends ConsumerStatefulWidget {
  final String announcementId;

  const AnnouncementDetailScreen({super.key, required this.announcementId});

  @override
  ConsumerState<AnnouncementDetailScreen> createState() =>
      _AnnouncementDetailScreenState();
}

class _AnnouncementDetailScreenState
    extends ConsumerState<AnnouncementDetailScreen> {
  bool _markedRead = false;

  void _maybeMarkRead(AppNotification? notification) {
    if (_markedRead || notification == null || notification.read) return;
    _markedRead = true;
    // Defer to after the current build to avoid mutating provider state
    // during the widget tree build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(notificationInboxProvider.notifier).markRead(notification);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final detail = ref.watch(announcementDetailProvider(widget.announcementId));

    return BisoPage(
      title: l10n.announcementTitle,
      largeTitle: false,
      leading: BisoBackButton(
        onPressed: () => NavigationUtils.safeGoBack(
          context,
          fallbackRoute: '/notifications',
        ),
      ),
      slivers: detail.when(
        loading: () => const [SliverToBoxAdapter(child: BisoSkeleton.rows())],
        error: (error, _) => [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoErrorState(
              message: error.toString(),
              onRetry: () => ref.invalidate(
                announcementDetailProvider(widget.announcementId),
              ),
            ),
          ),
        ],
        data: (notification) {
          if (notification == null) {
            return [
              SliverFillRemaining(
                hasScrollBody: false,
                child: BisoEmptyState(
                  icon: CupertinoIcons.tray,
                  title: l10n.announcementNotFoundTitle,
                  message: l10n.announcementNotFoundMessage,
                ),
              ),
            ];
          }
          _maybeMarkRead(notification);
          return _announcementSlivers(context, notification);
        },
      ),
    );
  }
}

List<Widget> _announcementSlivers(
  BuildContext context,
  AppNotification notification,
) {
  final theme = Theme.of(context);
  final palette = BisoPalette.of(context);
  final hasHtml = notification.bodyHtml.trim().isNotEmpty;

  return [
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    _categoryLabel(
                      AppLocalizations.of(context)!,
                      notification.category,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              notification.title,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _formatTimestamp(context, notification.createdAt),
              style: theme.textTheme.labelMedium?.copyWith(
                color: palette.muted,
              ),
            ),
          ],
        ),
      ),
    ),
    SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Material(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: hasHtml
                ? PremiumHtmlRenderer.full(htmlContent: notification.bodyHtml)
                : Text(
                    notification.body.isNotEmpty
                        ? notification.body
                        : AppLocalizations.of(context)!.announcementNoContent,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.5,
                      color: palette.ink,
                    ),
                  ),
          ),
        ),
      ),
    ),
    if (notification.items.isNotEmpty)
      SliverToBoxAdapter(
        child: BisoSection(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: BisoListGroup(
            dividerIndent: kInboxThumbDividerIndent,
            children: [
              for (final item in notification.items)
                InboxItemRow(
                  key: ValueKey('${item.type}-${item.id}'),
                  item: item,
                  onTap: () => context.go(item.route),
                ),
            ],
          ),
        ),
      ),
    if (notification.eventId != null && notification.eventId!.isNotEmpty)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                DeepLinkService().handleDeepLink(
                  Uri.parse('biso://event?id=${notification.eventId}'),
                );
              },
              icon: const Icon(CupertinoIcons.calendar),
              label: Text(AppLocalizations.of(context)!.announcementViewEvent),
            ),
          ),
        ),
      ),
  ];
}

String _categoryLabel(AppLocalizations l10n, String category) {
  switch (category) {
    case 'urgent':
      return l10n.inboxCategoryUrgent;
    case 'trip':
      return l10n.inboxCategoryTrip;
    case 'event':
      return l10n.inboxCategoryEvent;
    default:
      return l10n.inboxCategoryGeneral;
  }
}

String _formatTimestamp(BuildContext context, DateTime date) {
  final local = date.toLocal();
  final material = MaterialLocalizations.of(context);
  final time = material.formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat: true,
  );
  return '${material.formatMediumDate(local)} · $time';
}
