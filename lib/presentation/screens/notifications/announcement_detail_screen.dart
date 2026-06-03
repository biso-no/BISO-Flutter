import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/app_notification_model.dart';
import '../../../data/services/deep_link_service.dart';
import '../../../providers/notification/notification_provider.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Announcement'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () =>
              NavigationUtils.safeGoBack(context, fallbackRoute: '/notifications'),
        ),
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(
            announcementDetailProvider(widget.announcementId),
          ),
        ),
        data: (notification) {
          if (notification == null) {
            return const _NotFoundView();
          }
          _maybeMarkRead(notification);
          return _AnnouncementBody(notification: notification);
        },
      ),
    );
  }
}

class _AnnouncementBody extends StatelessWidget {
  final AppNotification notification;

  const _AnnouncementBody({required this.notification});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoryColor = _categoryColor(notification.category);
    final hasHtml = notification.bodyHtml.trim().isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: categoryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _categoryIcon(notification.category),
                color: categoryColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            _CategoryChip(
              category: notification.category,
              color: categoryColor,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          notification.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _formatTimestamp(notification.createdAt),
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppColors.gray500,
          ),
        ),
        const SizedBox(height: 20),
        const Divider(height: 1),
        const SizedBox(height: 16),
        if (hasHtml)
          PremiumHtmlRenderer.full(htmlContent: notification.bodyHtml)
        else if (notification.body.isNotEmpty)
          Text(
            notification.body,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          )
        else
          Text(
            'No content.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.gray500,
            ),
          ),
        if (notification.eventId != null &&
            notification.eventId!.isNotEmpty) ...[
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                DeepLinkService().handleDeepLink(
                  Uri.parse('biso://event?id=${notification.eventId}'),
                );
              },
              icon: const Icon(Icons.event_rounded),
              label: const Text('View event'),
            ),
          ),
        ],
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String category;
  final Color color;

  const _CategoryChip({required this.category, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _categoryLabel(category),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _NotFoundView extends StatelessWidget {
  const _NotFoundView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
        const Icon(
          Icons.inbox_rounded,
          size: 64,
          color: AppColors.gray400,
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Announcement not found',
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'It may have been removed.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.gray500,
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
        const Icon(
          Icons.error_outline_rounded,
          size: 64,
          color: AppColors.error,
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Could not load announcement',
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.gray500,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ),
      ],
    );
  }
}

Color _categoryColor(String category) {
  switch (category) {
    case 'urgent':
      return AppColors.error;
    case 'trip':
      return AppColors.orange9;
    case 'event':
      return AppColors.defaultBlue;
    default:
      return AppColors.biLightBlue;
  }
}

IconData _categoryIcon(String category) {
  switch (category) {
    case 'urgent':
      return Icons.priority_high_rounded;
    case 'trip':
      return Icons.flight_takeoff_rounded;
    case 'event':
      return Icons.event_rounded;
    default:
      return Icons.campaign_rounded;
  }
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
