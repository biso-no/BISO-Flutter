import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/app_notification_model.dart';
import '../../../data/services/deep_link_service.dart';
import '../../../providers/notification/notification_provider.dart';
import '../../widgets/biso/biso.dart';

/// In-app notification inbox. Lists announcements addressed to the current
/// user (broadcast + targeted) and lets them open the linked content.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationInboxProvider);

    return BisoPage(
      title: 'Notifications',
      leading: BisoBackButton(
        onPressed: () => NavigationUtils.safeGoBack(context),
      ),
      onRefresh: () => ref.read(notificationInboxProvider.notifier).refresh(),
      slivers: _buildSlivers(ref, state),
    );
  }

  List<Widget> _buildSlivers(WidgetRef ref, NotificationInboxState state) {
    if (state.isLoading && state.items.isEmpty) {
      return const [SliverToBoxAdapter(child: BisoSkeleton.rows())];
    }

    if (state.error != null && state.items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: BisoErrorState(
            message: state.error,
            onRetry: () =>
                ref.read(notificationInboxProvider.notifier).load(),
          ),
        ),
      ];
    }

    if (state.items.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: BisoEmptyState(
            icon: CupertinoIcons.bell,
            title: 'No notifications yet',
            message: 'Updates from BISO will appear here.',
          ),
        ),
      ];
    }

    return [
      SliverBisoListGroup(
        itemCount: state.items.length,
        itemBuilder: (context, index) {
          final item = state.items[index];
          return _NotificationRow(
            notification: item,
            onTap: () => _handleTap(context, ref, item),
          );
        },
      ),
    ];
  }

  Future<void> _handleTap(
    BuildContext context,
    WidgetRef ref,
    AppNotification item,
  ) async {
    await ref.read(notificationInboxProvider.notifier).markRead(item);

    if (item.deepLink != null && item.deepLink!.isNotEmpty) {
      final uri = Uri.tryParse(item.deepLink!);
      if (uri != null) {
        DeepLinkService().handleDeepLink(uri);
        return;
      }
    }

    if (item.eventId != null && item.eventId!.isNotEmpty) {
      DeepLinkService().handleDeepLink(
        Uri.parse('biso://event?id=${item.eventId}'),
      );
      return;
    }

    // No deep link or event: open the rich announcement detail directly.
    if (item.id.isNotEmpty && context.mounted) {
      context.go('/announcements/${item.id}');
    }
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final isUnread = !notification.read;

    return BisoListRow(
      leading: BisoIconTile(
        icon: _categoryIcon(notification.category),
        accent: _categoryAccent(notification.category),
      ),
      title: notification.title,
      subtitle: notification.body.isNotEmpty ? notification.body : null,
      value: _relativeTime(notification.createdAt),
      trailing: isUnread
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: palette.link,
                shape: BoxShape.circle,
              ),
              child: const SizedBox(width: 8, height: 8),
            )
          : null,
      onTap: onTap,
    );
  }
}

// The only topic this screen colors distinctly is `event`, matching R6's
// events/departures/calendar -> blue. `trip`, `urgent` and `general` have no
// counterpart in the shop/units/expenses topic set R6 documents, so they fall
// to the neutral bell the brief specifies as the default.
BisoAccent _categoryAccent(String category) =>
    category == 'event' ? BisoAccent.blue : BisoAccent.neutral;

IconData _categoryIcon(String category) {
  switch (category) {
    case 'urgent':
      return CupertinoIcons.exclamationmark_triangle;
    case 'trip':
      return CupertinoIcons.airplane;
    case 'event':
      return CupertinoIcons.calendar;
    default:
      return CupertinoIcons.bell;
  }
}

String _relativeTime(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
  return '${(diff.inDays / 365).floor()}y ago';
}
