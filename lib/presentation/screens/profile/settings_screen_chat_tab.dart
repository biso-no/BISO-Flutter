import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/notification/notification_provider.dart';
import '../../widgets/biso/biso.dart';
import '../../widgets/premium/notification_tile.dart';
import 'settings_screen.dart';

class ChatSettingsBody extends ConsumerWidget {
  const ChatSettingsBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(appSettingsProvider);
    final notificationPrefs = ref.watch(notificationPreferencesProvider);
    final notificationStatus = ref.watch(notificationStatusProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BisoSection(
          title: 'Chat Settings',
          child: BisoListGroup(
            children: [
              // Chat notifications with permission status
              notificationPrefs.when(
                data: (prefs) => buildNotificationTile(
                  icon: CupertinoIcons.bell,
                  title: 'Chat Notifications',
                  subtitle: notificationStatus.when(
                    data: (enabled) => enabled
                        ? 'Receive notifications for new messages'
                        : 'Enable system notifications first',
                    loading: () => 'Checking permissions...',
                    error: (_, _) => 'Receive notifications for new messages',
                  ),
                  isEnabled: prefs['chat_notifications'] ?? true,
                  onChanged: notificationStatus.when(
                    data: (systemEnabled) => systemEnabled
                        ? (value) async {
                            try {
                              await ref
                                  .read(notificationPreferencesProvider.notifier)
                                  .updateChatNotifications(value);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Failed to update setting: $e'),
                                    backgroundColor: BisoPalette.of(context).error,
                                  ),
                                );
                              }
                            }
                          }
                        : (value) async {
                            // Request permissions first
                            final service = ref.read(notificationServiceProvider);
                            final granted = await service.requestPermission();
                            if (granted && value) {
                              await ref
                                  .read(notificationPreferencesProvider.notifier)
                                  .updateChatNotifications(true);
                              // Refresh permission status
                              ref.invalidate(notificationStatusProvider);
                            } else if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Please enable notifications in system settings',
                                  ),
                                  backgroundColor: BisoPalette.of(context).error,
                                ),
                              );
                            }
                          },
                    loading: () => null,
                    error: (_, _) => null,
                  ),
                ),
                loading: () => buildLoadingTile('Loading notification settings...'),
                error: (error, _) =>
                    buildErrorTile('Error loading notification settings', error.toString()),
              ),
              BisoListRow(
                leading: const BisoIconTile(icon: CupertinoIcons.waveform),
                title: 'Vibration',
                subtitle: 'Vibrate for new messages',
                trailing: Switch.adaptive(
                  value: settingsState.notifications['chat_vibration'] ?? true,
                  onChanged: (value) {
                    ref
                        .read(appSettingsProvider.notifier)
                        .setNotification('chat_vibration', value);
                  },
                ),
              ),
              BisoListRow(
                leading: const BisoIconTile(icon: CupertinoIcons.volume_up),
                title: 'Sound',
                subtitle: 'Play sound for new messages',
                trailing: Switch.adaptive(
                  value: settingsState.notifications['chat_sound'] ?? true,
                  onChanged: (value) {
                    ref.read(appSettingsProvider.notifier).setNotification('chat_sound', value);
                  },
                ),
              ),
            ],
          ),
        ),

        BisoSection(
          title: 'Chat Behavior',
          child: BisoListGroup(
            children: [
              BisoListRow(
                leading: const BisoIconTile(icon: CupertinoIcons.eye),
                title: 'Read Receipts',
                subtitle: 'Let others know when you\'ve read their messages',
                trailing: Switch.adaptive(
                  value: settingsState.notifications['read_receipts'] ?? true,
                  onChanged: (value) {
                    ref.read(appSettingsProvider.notifier).setNotification('read_receipts', value);
                  },
                ),
              ),
              BisoListRow(
                leading: const BisoIconTile(icon: CupertinoIcons.pencil),
                title: 'Typing Indicators',
                subtitle: 'Show when you\'re typing',
                trailing: Switch.adaptive(
                  value: settingsState.notifications['typing_indicators'] ?? true,
                  onChanged: (value) {
                    ref
                        .read(appSettingsProvider.notifier)
                        .setNotification('typing_indicators', value);
                  },
                ),
              ),
              BisoListRow(
                leading: const BisoIconTile(icon: CupertinoIcons.clock),
                title: 'Last Seen',
                subtitle: 'Show your last seen status',
                trailing: Switch.adaptive(
                  value: settingsState.notifications['last_seen'] ?? true,
                  onChanged: (value) {
                    ref.read(appSettingsProvider.notifier).setNotification('last_seen', value);
                  },
                ),
              ),
            ],
          ),
        ),

        BisoSection(
          title: 'Chat Storage',
          footer:
              'Chat settings apply to all conversations. Individual chat settings can be '
              'changed from the chat info screen.',
          child: BisoListGroup(
            children: [
              BisoListRow(
                leading: const BisoIconTile(icon: CupertinoIcons.trash),
                title: 'Auto-delete Messages',
                subtitle: 'Automatically delete old messages',
                value: 'Never',
                showChevron: false,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Auto-delete options coming soon')),
                  );
                },
              ),
              BisoListRow(
                leading: const BisoIconTile(icon: CupertinoIcons.arrow_down_circle),
                title: 'Auto-download Media',
                subtitle: 'Download photos and files automatically',
                value: 'Wi-Fi only',
                showChevron: false,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Auto-download options coming soon')),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
