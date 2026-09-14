import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/app_notification_model.dart';
import '../../../data/services/deep_link_service.dart';
import '../../../providers/notification/notification_provider.dart';
import '../../widgets/biso/biso.dart';
import '../../widgets/premium/premium_html_renderer.dart';

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
    final detail = ref.watch(announcementDetailProvider(widget.announcementId));

    return BisoPage(
      title: 'Announcement',
      largeTitle: false,
      leading: BisoBackButton(
        onPressed: () =>
            NavigationUtils.safeGoBack(context, fallbackRoute: '/notifications'),
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
            return const [
              SliverFillRemaining(
                hasScrollBody: false,
                child: BisoEmptyState(
                  icon: CupertinoIcons.tray,
                  title: 'Announcement not found',
                  message: 'It may have been removed.',
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
              children: [Chip(label: Text(_categoryLabel(notification.category)))],
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
              _formatTimestamp(notification.createdAt),
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
                        : 'No content.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.5,
                      color: palette.ink,
                    ),
                  ),
          ),
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
              label: const Text('View event'),
            ),
          ),
        ),
      ),
  ];
}

String _categoryLabel(String category) {
  switch (category) {
    case 'urgent':
      return 'Urgent';
    case 'trip':
      return 'Trip';
    case 'event':
      return 'Event';
    default:
      return 'General';
  }
}

String _formatTimestamp(DateTime date) {
  final local = date.toLocal();
  final months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = months[local.month - 1];
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month ${local.day}, ${local.year} · $hour:$minute';
}
