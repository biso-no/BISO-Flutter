import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/notification_topics.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../../providers/privacy/privacy_provider.dart';
import '../../../providers/ui/locale_provider.dart';
import '../../../providers/ui/theme_mode_provider.dart';
import '../../../providers/notification/notification_provider.dart';
import '../../../data/services/notification_service.dart' show ReconcileOutcome;
import '../../../data/services/validator_service.dart';
import '../../widgets/biso/biso.dart';
import '../../widgets/premium/notification_tile.dart';
import 'settings_screen_chat_tab.dart';

// Settings providers
final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettingsState>((ref) {
      return AppSettingsNotifier();
    });

// Controller permissions provider
final controllerPermissionsProvider = FutureProvider<bool>((ref) async {
  final validatorService = ValidatorService();
  return await validatorService.hasControllerPermissions();
});

class AppSettingsState {
  final bool darkMode;
  final String language;
  final Map<String, bool> notifications;
  final bool isLoading;

  const AppSettingsState({
    this.darkMode = false,
    this.language = 'en',
    this.notifications = const {
      'events': true,
      'products': true,
      'jobs': true,
      'expenses': false,
      'chat': true,
    },
    this.isLoading = false,
  });

  AppSettingsState copyWith({
    bool? darkMode,
    String? language,
    Map<String, bool>? notifications,
    bool? isLoading,
  }) {
    return AppSettingsState(
      darkMode: darkMode ?? this.darkMode,
      language: language ?? this.language,
      notifications: notifications ?? this.notifications,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AppSettingsNotifier extends StateNotifier<AppSettingsState> {
  AppSettingsNotifier() : super(const AppSettingsState()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    state = state.copyWith(isLoading: true);

    try {
      final prefs = await SharedPreferences.getInstance();

      final darkMode = prefs.getBool('dark_mode') ?? false;
      final language = prefs.getString('language') ?? 'en';

      // Load notification preferences
      final notifications = Map<String, bool>.from(state.notifications);
      for (final key in notifications.keys) {
        notifications[key] =
            prefs.getBool('notification_$key') ?? notifications[key]!;
      }

      state = state.copyWith(
        darkMode: darkMode,
        language: language,
        notifications: notifications,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> setDarkMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', enabled);
    state = state.copyWith(darkMode: enabled);
  }

  Future<void> setLanguage(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', language);
    state = state.copyWith(language: language);
  }

  Future<void> setNotification(String key, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notification_$key', enabled);

    final updatedNotifications = Map<String, bool>.from(state.notifications);
    updatedNotifications[key] = enabled;
    state = state.copyWith(notifications: updatedNotifications);
  }
}

/// The sections Settings is split into. Each one is its own page, pushed
/// with a [MaterialPageRoute] from the [SettingsScreen] list.
enum SettingsSection { general, notifications, privacy, chat, language }

/// The [RouteSettings.name] every route that is part of Settings is pushed
/// with — the [SettingsScreen] list itself, and every [SettingsSectionPage],
/// whether it was pushed from that list or directly from a caller (such as
/// `ProfileScreen`'s direct links to the notifications or language section).
///
/// This lets the Account row's back navigation ([_GeneralSettingsBody]) pop
/// every Settings route in one call, regardless of how many of them are on
/// the stack: one when its section page was pushed directly, two when it
/// was reached through the list.
const kSettingsRouteName = 'settings';

/// A grouped list of the settings sections. Tapping a row pushes its
/// [SettingsSectionPage].
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    Widget row({
      required SettingsSection section,
      required String title,
      required IconData icon,
      BisoAccent accent = BisoAccent.neutral,
    }) {
      return BisoListRow(
        leading: BisoIconTile(icon: icon, accent: accent),
        title: title,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SettingsSectionPage(section: section),
            settings: const RouteSettings(name: kSettingsRouteName),
          ),
        ),
      );
    }

    return BisoPage(
      title: l10n.settingsMessage,
      slivers: [
        SliverToBoxAdapter(
          child: BisoSection(
            child: BisoListGroup(
              children: [
                row(
                  section: SettingsSection.general,
                  title: l10n.generalMessage,
                  icon: CupertinoIcons.gear,
                ),
                row(
                  section: SettingsSection.notifications,
                  title: l10n.notificationsMessage,
                  icon: CupertinoIcons.bell,
                ),
                row(
                  section: SettingsSection.privacy,
                  title: l10n.privacyMessage,
                  icon: CupertinoIcons.lock,
                ),
                row(
                  section: SettingsSection.chat,
                  title: l10n.chatMessage,
                  icon: CupertinoIcons.bubble_left_bubble_right,
                  accent: BisoAccent.teal,
                ),
                row(
                  section: SettingsSection.language,
                  title: l10n.languageMessage,
                  icon: CupertinoIcons.globe,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One settings section's own page, reached from [SettingsScreen].
class SettingsSectionPage extends StatelessWidget {
  const SettingsSectionPage({super.key, required this.section});

  final SettingsSection section;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (title, body) = switch (section) {
      SettingsSection.general => (l10n.generalMessage, const _GeneralSettingsBody()),
      SettingsSection.notifications => (
        l10n.notificationsMessage,
        const _NotificationSettingsBody(),
      ),
      SettingsSection.privacy => (l10n.privacyMessage, const _PrivacySettingsBody()),
      SettingsSection.chat => (l10n.chatMessage, const ChatSettingsBody()),
      SettingsSection.language => (l10n.languageMessage, const _LanguageSettingsBody()),
    };

    return BisoPage(
      title: title,
      largeTitle: false,
      slivers: [SliverToBoxAdapter(child: body)],
    );
  }
}

/// A rounded surface block for a loading spinner or an error message with a
/// retry action, matching the shape of the [BisoListGroup] cards around it.
class _CardBlock extends StatelessWidget {
  const _CardBlock({required this.child, this.padding = const EdgeInsets.all(24)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
    color: BisoPalette.of(context).surface,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class _GeneralSettingsBody extends ConsumerWidget {
  const _GeneralSettingsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    final authState = ref.watch(authStateProvider);
    final selectedCampus = ref.watch(selectedCampusProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BisoSection(
          title: 'Account',
          child: BisoListGroup(
            children: [
              BisoListRow(
                leading: CircleAvatar(
                  backgroundColor: palette.link.withValues(alpha: 0.1),
                  child: Text(
                    authState.user?.name.substring(0, 1).toUpperCase() ?? 'U',
                    style: TextStyle(color: palette.link, fontWeight: FontWeight.bold),
                  ),
                ),
                title: authState.user?.name ?? 'User',
                subtitle: authState.user?.email ?? '',
                // Closes every Settings route in one call, landing on
                // whatever is underneath — Profile, however many Settings
                // routes (the list, this section page, or both) are on top.
                onTap: () => Navigator.of(
                  context,
                ).popUntil((route) => route.settings.name != kSettingsRouteName),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const BisoIconTile(icon: CupertinoIcons.brightness),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Appearance',
                            style: text.titleMedium?.copyWith(color: palette.ink),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 44),
                      child: Text(
                        'Choose a theme or follow your system setting',
                        style: text.bodySmall?.copyWith(color: palette.muted),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(CupertinoIcons.device_phone_portrait),
                            label: Text('System'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(CupertinoIcons.sun_max),
                            label: Text('Light'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(CupertinoIcons.moon),
                            label: Text('Dark'),
                          ),
                        ],
                        selected: {themeMode},
                        onSelectionChanged: (selection) {
                          ref.read(themeModeProvider.notifier).setThemeMode(selection.first);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        BisoSection(
          title: 'Campus',
          child: BisoListGroup(
            children: [
              BisoListRow(
                leading: const BisoIconTile(icon: CupertinoIcons.location_solid),
                title: 'Current Campus',
                subtitle: 'BI ${selectedCampus.name}',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Use the campus switcher on the home screen to change campus',
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        // Controller Mode Section (only show if user has permissions)
        ref
            .watch(controllerPermissionsProvider)
            .when(
              data: (hasPermissions) => hasPermissions
                  ? BisoSection(
                      title: 'Validator Mode',
                      child: BisoListGroup(
                        children: [
                          BisoListRow(
                            leading: const BisoIconTile(
                              icon: CupertinoIcons.qrcode_viewfinder,
                            ),
                            title: 'Open Validator Mode',
                            subtitle: 'Scan student QR codes to verify membership',
                            onTap: () => context.push('/controller-mode'),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),

        BisoSection(
          title: 'Data & Storage',
          child: BisoListGroup(
            children: [
              BisoListRow(
                leading: const BisoIconTile(icon: CupertinoIcons.arrow_2_circlepath),
                title: 'Clear Cache',
                subtitle: 'Free up storage space',
                onTap: () => _showClearCacheDialog(context),
              ),
              BisoListRow(
                leading: const BisoIconTile(icon: CupertinoIcons.arrow_down_circle),
                title: 'Offline Data',
                subtitle: 'Manage downloaded content',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Offline data management coming soon')),
                  );
                },
              ),
            ],
          ),
        ),

        BisoSection(
          title: 'About',
          child: BisoListGroup(
            children: [
              const BisoListRow(
                leading: BisoIconTile(icon: CupertinoIcons.info_circle),
                title: 'App Version',
                subtitle: '1.0.0 (Build 1)',
              ),
              BisoListRow(
                leading: const BisoIconTile(icon: CupertinoIcons.shield),
                title: 'Privacy Policy',
                onTap: () => launchUrl(Uri.parse('https://biso.no/privacy')),
              ),
              BisoListRow(
                leading: const BisoIconTile(icon: CupertinoIcons.doc_text),
                title: 'Terms of Service',
                onTap: () => launchUrl(Uri.parse('https://biso.no/terms')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text(
          'This will clear all cached images and data. The app may take longer to load content after clearing cache.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cache cleared successfully')),
              );
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _NotificationSettingsBody extends ConsumerWidget {
  const _NotificationSettingsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notificationPrefsAsync = ref.watch(notificationPreferencesProvider);
    final topicIntentAsync = ref.watch(topicIntentProvider);
    final homeCampusId = ref.watch(
      authStateProvider.select((state) => state.user?.campusId),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BisoSection(
          title: 'Push Notifications',
          footer: homeCampusId == null
              ? 'You will receive national updates. Set your campus in your profile '
                    'to also get campus news.'
              : 'You receive updates for your campus and national updates.',
          child: topicIntentAsync.when(
            data: (intent) => BisoListGroup(
              children: [
                for (final topic in NotificationTopic.values)
                  buildNotificationTile(
                    icon: _topicIcon(topic),
                    accent: _topicAccent(topic),
                    title: topic.label,
                    subtitle: _topicSubtitle(topic),
                    isEnabled: intent[topic.id] ?? false,
                    onChanged: (value) async {
                      final result = await ref
                          .read(topicIntentProvider.notifier)
                          .setTopic(topic.id, value);
                      if (!context.mounted) return;
                      switch (result) {
                        case null:
                          // The save itself failed - nothing was recorded.
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Could not update ${topic.label} notifications. '
                                'Check your connection and try again.',
                              ),
                            ),
                          );
                          break;
                        case ReconcileOutcome.applied:
                          // Saved and this device is subscribed. No snackbar.
                          break;
                        case ReconcileOutcome.permissionDenied:
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Saved. Turn on notifications in your device '
                                'settings to receive them.',
                              ),
                            ),
                          );
                          break;
                        case ReconcileOutcome.unavailable:
                        case ReconcileOutcome.partiallyFailed:
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Saved, but this device could not be updated. '
                                'It will retry next time you open the app.',
                              ),
                            ),
                          );
                          break;
                      }
                    },
                  ),
              ],
            ),
            loading: () => const _CardBlock(child: Center(child: CircularProgressIndicator())),
            error: (error, _) => _CardBlock(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Could not load your notification settings.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => ref.read(topicIntentProvider.notifier).refresh(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),

        BisoSection(
          child: notificationPrefsAsync.when(
            data: (preferences) => BisoListGroup(
              children: [
                buildNotificationTile(
                  icon: CupertinoIcons.chat_bubble,
                  accent: BisoAccent.teal,
                  title: 'Chat Messages',
                  subtitle: 'New messages and conversations',
                  isEnabled: preferences['chat_notifications'] ?? true,
                  onChanged: (value) {
                    ref
                        .read(notificationPreferencesProvider.notifier)
                        .updateChatNotifications(value);
                  },
                ),
              ],
            ),
            loading: () => const _CardBlock(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stack) => _CardBlock(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.exclamationmark_circle,
                    size: 48,
                    color: BisoPalette.of(context).error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load notification preferences',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: BisoPalette.of(context).error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: BisoPalette.of(context).muted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      ref.read(notificationPreferencesProvider.notifier).refresh();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),

        BisoSection(
          title: 'Notification Schedule',
          child: BisoListGroup(
            children: [
              BisoListRow(
                leading: const BisoIconTile(icon: CupertinoIcons.clock),
                title: 'Quiet Hours',
                subtitle: 'Mute notifications during specific hours',
                trailing: Switch.adaptive(
                  value: false,
                  onChanged: (value) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Quiet hours feature coming soon')),
                    );
                  },
                ),
              ),
              BisoListRow(
                leading: const BisoIconTile(icon: CupertinoIcons.waveform),
                title: 'Vibration',
                subtitle: 'Vibrate for notifications',
                trailing: Switch.adaptive(
                  value: true,
                  onChanged: (value) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Vibration settings coming soon')),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

IconData _topicIcon(NotificationTopic topic) => switch (topic) {
  NotificationTopic.news => CupertinoIcons.news,
  NotificationTopic.events => CupertinoIcons.calendar,
  NotificationTopic.jobs => CupertinoIcons.briefcase,
  NotificationTopic.shop => CupertinoIcons.bag,
};

BisoAccent _topicAccent(NotificationTopic topic) => switch (topic) {
  NotificationTopic.news => BisoAccent.neutral,
  NotificationTopic.events => BisoAccent.blue,
  NotificationTopic.jobs => BisoAccent.teal,
  NotificationTopic.shop => BisoAccent.gold,
};

String _topicSubtitle(NotificationTopic topic) => switch (topic) {
  NotificationTopic.news => 'Articles and updates from BISO',
  NotificationTopic.events => 'New campus events and activities',
  NotificationTopic.jobs => 'Volunteer and job opportunities',
  NotificationTopic.shop => 'New items and offers in the BISO shop',
};

class _PrivacySettingsBody extends ConsumerWidget {
  const _PrivacySettingsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    if (authState.user == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: BisoSkeleton.rows(count: 2),
      );
    }

    final userId = authState.user!.id;
    final privacyStatusAsync = ref.watch(privacyStatusProvider(userId));
    final userPrivacyAsync = ref.watch(userPrivacyProvider(userId));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BisoSection(
          title: 'Chat Privacy',
          footer: privacyStatusAsync.hasError ? null : privacyStatusAsync.valueOrNull,
          child: BisoListGroup(
            children: [
              userPrivacyAsync.when(
                data: (isPublic) => BisoListRow(
                  leading: BisoIconTile(
                    icon: isPublic == true ? CupertinoIcons.globe : CupertinoIcons.lock,
                    accent: isPublic == true ? BisoAccent.teal : BisoAccent.neutral,
                  ),
                  title: 'Public Profile',
                  subtitle: isPublic == true
                      ? 'Others can find and message you'
                      : 'Others cannot find you in search',
                  trailing: Switch.adaptive(
                    value: isPublic == true,
                    onChanged: (value) async {
                      try {
                        final privacyNotifier = ref.read(
                          privacySettingProvider(userId).notifier,
                        );
                        await privacyNotifier.updatePrivacySetting(value);

                        // Refresh the privacy status
                        ref.invalidate(userPrivacyProvider(userId));
                        ref.invalidate(privacyStatusProvider(userId));

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                value
                                    ? 'Public profile created - others can find you in search'
                                    : 'Public profile removed - you won\'t appear in search',
                              ),
                              backgroundColor: BisoPalette.of(context).link,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to update privacy setting: $e'),
                              backgroundColor: BisoPalette.of(context).error,
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
                loading: () => buildLoadingTile('Loading privacy settings...'),
                error: (error, stack) =>
                    buildErrorTile('Error loading privacy settings', error.toString()),
              ),
            ],
          ),
        ),

        BisoSection(
          title: 'Privacy Information',
          child: BisoListGroup(
            children: [
              _PrivacyInfoRow(
                icon: CupertinoIcons.globe,
                accent: BisoAccent.teal,
                title: 'Public Profile',
                bullets:
                    '• Others can find you in user search\n'
                    '• Students can start conversations with you\n'
                    '• You appear in recent contacts\n'
                    '• You can still control who messages you',
              ),
              _PrivacyInfoRow(
                icon: CupertinoIcons.lock,
                accent: BisoAccent.neutral,
                title: 'Private Profile',
                bullets:
                    '• Others cannot find you in search\n'
                    '• You can still message others\n'
                    '• Only you can start new conversations\n'
                    '• Existing conversations remain active',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A row of descriptive bullet text, too long for [BisoListRow]'s two-line
/// subtitle, explaining one privacy state.
class _PrivacyInfoRow extends StatelessWidget {
  const _PrivacyInfoRow({
    required this.icon,
    required this.accent,
    required this.title,
    required this.bullets,
  });

  final IconData icon;
  final BisoAccent accent;
  final String title;
  final String bullets;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BisoIconTile(icon: icon, accent: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleMedium?.copyWith(color: palette.ink)),
                const SizedBox(height: 6),
                Text(
                  bullets,
                  style: text.bodyMedium?.copyWith(color: palette.muted, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageSettingsBody extends ConsumerWidget {
  const _LanguageSettingsBody();

  static const _languages = [
    {'code': 'en', 'name': 'English', 'nativeName': 'English'},
    {'code': 'no', 'name': 'Norwegian', 'nativeName': 'Norsk'},
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(localeProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BisoSection(
          title: 'App Language',
          footer: 'Language changes will take effect immediately.',
          child: BisoListGroup(
            children: [
              for (final language in _languages)
                BisoListRow(
                  title: language['name']!,
                  subtitle: language['nativeName']!,
                  trailing: Radio<String>(
                    value: language['code']!,
                    groupValue: currentLocale.languageCode,
                    onChanged: (value) {
                      if (value != null && value != currentLocale.languageCode) {
                        ref.read(localeProvider.notifier).setLocale(value);
                      }
                    },
                  ),
                  onTap: () {
                    final code = language['code']!;
                    if (code != currentLocale.languageCode) {
                      ref.read(localeProvider.notifier).setLocale(code);
                    }
                  },
                ),
            ],
          ),
        ),

        BisoSection(
          title: 'Regional Settings',
          child: BisoListGroup(
            children: [
              BisoListRow(
                leading: const BisoIconTile(icon: CupertinoIcons.clock),
                title: 'Date Format',
                subtitle: 'DD/MM/YYYY (Norwegian)',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Date format options coming soon')),
                  );
                },
              ),
              BisoListRow(
                leading: const BisoIconTile(icon: CupertinoIcons.money_dollar_circle),
                title: 'Currency',
                subtitle: 'NOK (Norwegian Krone)',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Currency is automatically set to NOK for BI students',
                      ),
                    ),
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
