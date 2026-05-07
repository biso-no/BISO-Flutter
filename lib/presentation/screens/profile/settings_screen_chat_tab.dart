import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../../providers/notification/notification_provider.dart';
import 'settings_screen.dart';

class ChatSettingsTab extends ConsumerWidget {
  const ChatSettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settingsState = ref.watch(appSettingsProvider);
    final selectedCampus = ref.watch(selectedCampusProvider);
    final notificationPrefs = ref.watch(notificationPreferencesProvider);
    final notificationStatus = ref.watch(notificationStatusProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 132),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chat Settings',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.strongBlue,
            ),
          ),

          const SizedBox(height: 12),

          Card(
            child: Column(
              children: [
                // Chat notifications with permission status
                notificationPrefs.when(
                  data: (prefs) => SwitchListTile(
                    secondary: const Icon(
                      Icons.notifications,
                      color: AppColors.onSurfaceVariant,
                    ),
                    title: const Text('Chat Notifications'),
                    subtitle: notificationStatus.when(
                      data: (enabled) => Text(
                        enabled
                            ? 'Receive notifications for new messages'
                            : 'Enable system notifications first',
                      ),
                      loading: () => const Text('Checking permissions...'),
                      error: (_, _) =>
                          const Text('Receive notifications for new messages'),
                    ),
                    value: prefs['chat_notifications'] ?? true,
                    onChanged: notificationStatus.when(
                      data: (systemEnabled) => systemEnabled
                          ? (value) async {
                              try {
                                await ref
                                    .read(
                                      notificationPreferencesProvider.notifier,
                                    )
                                    .updateChatNotifications(value);
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Failed to update setting: $e',
                                      ),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                }
                              }
                            }
                          : (value) async {
                              // Request permissions first
                              final service = ref.read(
                                notificationServiceProvider,
                              );
                              final granted = await service.requestPermission();
                              if (granted && value) {
                                await ref
                                    .read(
                                      notificationPreferencesProvider.notifier,
                                    )
                                    .updateChatNotifications(true);
                                // Refresh permission status
                                ref.invalidate(notificationStatusProvider);
                              } else if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Please enable notifications in system settings',
                                    ),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                              }
                            },
                      loading: () => null,
                      error: (_, _) => null,
                    ),
                    thumbColor: campusSwitchThumbColor(
                      _getCampusColor(selectedCampus.id),
                    ),
                    trackColor: campusSwitchTrackColor(
                      _getCampusColor(selectedCampus.id),
                    ),
                  ),
                  loading: () => const ListTile(
                    leading: CircularProgressIndicator(),
                    title: Text('Loading notification settings...'),
                  ),
                  error: (error, _) => ListTile(
                    leading: const Icon(
                      Icons.error_outline,
                      color: AppColors.error,
                    ),
                    title: const Text('Error loading notification settings'),
                    subtitle: Text(error.toString()),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(
                    Icons.vibration,
                    color: AppColors.onSurfaceVariant,
                  ),
                  title: const Text('Vibration'),
                  subtitle: const Text('Vibrate for new messages'),
                  value: settingsState.notifications['chat_vibration'] ?? true,
                  onChanged: (value) {
                    ref
                        .read(appSettingsProvider.notifier)
                        .setNotification('chat_vibration', value);
                  },
                  thumbColor: campusSwitchThumbColor(
                    _getCampusColor(selectedCampus.id),
                  ),
                  trackColor: campusSwitchTrackColor(
                    _getCampusColor(selectedCampus.id),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(
                    Icons.volume_up,
                    color: AppColors.onSurfaceVariant,
                  ),
                  title: const Text('Sound'),
                  subtitle: const Text('Play sound for new messages'),
                  value: settingsState.notifications['chat_sound'] ?? true,
                  onChanged: (value) {
                    ref
                        .read(appSettingsProvider.notifier)
                        .setNotification('chat_sound', value);
                  },
                  thumbColor: campusSwitchThumbColor(
                    _getCampusColor(selectedCampus.id),
                  ),
                  trackColor: campusSwitchTrackColor(
                    _getCampusColor(selectedCampus.id),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'Chat Behavior',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.strongBlue,
            ),
          ),

          const SizedBox(height: 12),

          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(
                    Icons.visibility,
                    color: AppColors.onSurfaceVariant,
                  ),
                  title: const Text('Read Receipts'),
                  subtitle: const Text(
                    'Let others know when you\'ve read their messages',
                  ),
                  value: settingsState.notifications['read_receipts'] ?? true,
                  onChanged: (value) {
                    ref
                        .read(appSettingsProvider.notifier)
                        .setNotification('read_receipts', value);
                  },
                  thumbColor: campusSwitchThumbColor(
                    _getCampusColor(selectedCampus.id),
                  ),
                  trackColor: campusSwitchTrackColor(
                    _getCampusColor(selectedCampus.id),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(
                    Icons.edit,
                    color: AppColors.onSurfaceVariant,
                  ),
                  title: const Text('Typing Indicators'),
                  subtitle: const Text('Show when you\'re typing'),
                  value:
                      settingsState.notifications['typing_indicators'] ?? true,
                  onChanged: (value) {
                    ref
                        .read(appSettingsProvider.notifier)
                        .setNotification('typing_indicators', value);
                  },
                  thumbColor: campusSwitchThumbColor(
                    _getCampusColor(selectedCampus.id),
                  ),
                  trackColor: campusSwitchTrackColor(
                    _getCampusColor(selectedCampus.id),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(
                    Icons.access_time,
                    color: AppColors.onSurfaceVariant,
                  ),
                  title: const Text('Last Seen'),
                  subtitle: const Text('Show your last seen status'),
                  value: settingsState.notifications['last_seen'] ?? true,
                  onChanged: (value) {
                    ref
                        .read(appSettingsProvider.notifier)
                        .setNotification('last_seen', value);
                  },
                  thumbColor: campusSwitchThumbColor(
                    _getCampusColor(selectedCampus.id),
                  ),
                  trackColor: campusSwitchTrackColor(
                    _getCampusColor(selectedCampus.id),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'Chat Storage',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.strongBlue,
            ),
          ),

          const SizedBox(height: 12),

          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.auto_delete,
                    color: AppColors.onSurfaceVariant,
                  ),
                  title: const Text('Auto-delete Messages'),
                  subtitle: const Text('Automatically delete old messages'),
                  trailing: const Text('Never'),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Auto-delete options coming soon'),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.download,
                    color: AppColors.onSurfaceVariant,
                  ),
                  title: const Text('Auto-download Media'),
                  subtitle: const Text(
                    'Download photos and files automatically',
                  ),
                  trailing: const Text('Wi-Fi only'),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Auto-download options coming soon'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? AppColors.midNavy.withValues(alpha: 0.5)
                  : AppColors.subtleBlue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: theme.brightness == Brightness.dark
                      ? AppColors.skyBlue
                      : AppColors.defaultBlue,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Chat settings apply to all conversations. Individual chat settings can be changed from the chat info screen.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.brightness == Brightness.dark
                          ? AppColors.skyBlue
                          : AppColors.defaultBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getCampusColor(String campusId) {
    switch (campusId) {
      case 'oslo':
        return AppColors.defaultBlue;
      case 'bergen':
        return AppColors.green9;
      case 'trondheim':
        return AppColors.purple9;
      case 'stavanger':
        return AppColors.orange9;
      default:
        return AppColors.gray400;
    }
  }
}
