import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../providers/auth/auth_provider.dart';
import '../../providers/notification/notification_provider.dart';

class NotificationPermissionDialog extends ConsumerWidget {
  const NotificationPermissionDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.subtleBlue,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.notifications_outlined,
              color: AppColors.defaultBlue,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Enable Notifications',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Stay connected with your campus community! Get notified about new messages, events, job opportunities, and marketplace items.',
            style: TextStyle(fontSize: 16, height: 1.4),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.subtleBlue,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: AppColors.defaultBlue,
                  size: 20,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You can change this setting anytime in your profile.',
                    style: TextStyle(
                      color: AppColors.defaultBlue,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(false);
          },
          child: const Text(
            'Not Now',
            style: TextStyle(color: AppColors.onSurfaceVariant),
          ),
        ),
        ElevatedButton(
          onPressed: () async {
            try {
              final service = ref.read(notificationServiceProvider);
              final granted = await service.requestPermission();

              if (granted) {
                // Enable chat notifications and default topic subscriptions
                final notifier = ref.read(notificationPreferencesProvider.notifier);
                await notifier.updateChatNotifications(true);

                // `products` was never a real topic, and `events`/`jobs` are
                // replaced by campus-scoped ids later in this plan. Also,
                // force-enabling three content topics here silently overrode
                // a choice the student may have already made elsewhere —
                // reconciling applies their recorded intent instead.
                await ref
                    .read(notificationServiceProvider)
                    .reconcile(
                      campusId: ref.read(authStateProvider).user?.campusId,
                    );

                if (context.mounted) {
                  Navigator.of(context).pop(true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('🎉 Notifications enabled! You\'ll stay updated on everything happening at BI.'),
                      backgroundColor: AppColors.defaultBlue,
                      duration: Duration(seconds: 4),
                    ),
                  );
                }
              } else {
                if (context.mounted) {
                  Navigator.of(context).pop(false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Please enable notifications in system settings',
                      ),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            } catch (e) {
              if (context.mounted) {
                Navigator.of(context).pop(false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error enabling notifications: $e'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.defaultBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('Enable'),
        ),
      ],
    );
  }

  /// Show the notification permission dialog
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const NotificationPermissionDialog(),
    );
  }
}
