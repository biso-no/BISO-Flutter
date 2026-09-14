import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/chat_model.dart';
import '../../../data/services/chat_service.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/privacy/privacy_provider.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../widgets/privacy_prompt_dialog.dart';
import '../../widgets/notification_permission_dialog.dart';
import '../../../providers/notification/notification_provider.dart';
import 'chat_conversation_screen.dart';
import 'chat_info_screen.dart';
import 'message_search_screen.dart';
import 'new_chat_screen.dart';
import '../profile/settings_screen.dart';

// Provider for chat service
final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService();
});

// Provider for user chats
final userChatsProvider = FutureProvider.family<List<ChatModel>, String>((
  ref,
  userId,
) async {
  final chatService = ref.read(chatServiceProvider);

  try {
    // Subscribe to real-time updates
    chatService.subscribeToUpdates(userId);

    // Get initial chats
    final chats = await chatService.getUserChats(userId);
    return chats;
  } catch (e) {
    return <ChatModel>[]; // Return empty list on error
  }
});

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'all';
  late final ChatService _chatService;

  final List<String> _chatFilters = [
    'all',
    'direct',
    'group',
    'team',
    'department',
  ];

  @override
  void initState() {
    super.initState();
    // Initialize chat service reference
    _chatService = ref.read(chatServiceProvider);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });

    // Check privacy and notification settings after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPrivacySettings();
      _checkNotificationPermissions();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    // Dispose chat service using stored reference
    _chatService.dispose();
    super.dispose();
  }

  Future<void> _checkPrivacySettings() async {
    final authState = ref.read(authStateProvider);
    if (authState.user == null) return;

    final userId = authState.user!.id;
    final shouldPrompt = await ref.read(
      shouldPromptPrivacyProvider(userId).future,
    );

    if (shouldPrompt && mounted) {
      _showPrivacyPrompt();
    }
  }

  void _showPrivacyPrompt() {
    final authState = ref.read(authStateProvider);
    if (authState.user == null) return;

    showDialog(
      context: context,
      barrierDismissible: false, // User must make a choice
      builder: (context) => PrivacyPromptDialog(
        onAcceptPublic: () async {
          Navigator.of(context).pop();
          await _setPrivacySetting(true);
        },
        onChoosePrivate: () async {
          Navigator.of(context).pop();
          await _setPrivacySetting(false);
        },
      ),
    );
  }

  Future<void> _setPrivacySetting(bool isPublic) async {
    final authState = ref.read(authStateProvider);
    if (authState.user == null) return;

    try {
      final privacyService = ref.read(privacyServiceProvider);
      await privacyService.setUserPrivacySetting(authState.user!.id, isPublic);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isPublic
                  ? 'Profile set to public - others can find and message you'
                  : 'Profile set to private - others cannot find you in search',
            ),
            backgroundColor: AppColors.defaultBlue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update privacy setting: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _checkNotificationPermissions() async {
    final authState = ref.read(authStateProvider);
    if (authState.user == null) return;

    try {
      final notificationService = ref.read(notificationServiceProvider);
      final isEnabled = await notificationService.areNotificationsEnabled();

      // Check if push target exists (indicates proper setup)
      final hasPushTarget = notificationService.pushTargetId != null;

      // Only prompt if notifications are not enabled or push target is missing
      if ((!isEnabled || !hasPushTarget) && mounted) {
        // Add a small delay to avoid conflicting with privacy prompt
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          _showNotificationPermissionPrompt();
        }
      }
    } catch (e) {
      // Silently fail - notification permission is not critical for chat functionality
    }
  }

  void _showNotificationPermissionPrompt() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const NotificationPermissionDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final authState = ref.watch(authStateProvider);

    if (authState.user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    

    final userId = authState.user!.id;
    final chatsAsync = ref.watch(userChatsProvider(userId));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.chatMessage),
        leading: IconButton(
          onPressed: () {
            // Navigate back to home screen (chat tab)
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            onPressed: () => _showSearchDialog(context),
            icon: const Icon(Icons.search),
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      const SettingsSectionPage(section: SettingsSection.chat),
                ),
              );
            },
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Tabs
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _chatFilters.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = _chatFilters[index];
                final isSelected = _selectedFilter == filter;

                return FilterChip(
                  label: Text(_getFilterDisplayName(filter)),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedFilter = filter;
                    });
                  },
                  backgroundColor: Colors.transparent,
                  selectedColor: AppColors.subtleBlue,
                  checkmarkColor: AppColors.defaultBlue,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? AppColors.defaultBlue
                        : AppColors.onSurfaceVariant,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: isSelected
                        ? AppColors.defaultBlue
                        : AppColors.outline,
                  ),
                );
              },
            ),
          ),

          const Divider(height: 1),

          // Chat List
          Expanded(
            child: chatsAsync.when(
              data: (chats) {
                final filteredChats = _filterChats(chats);

                if (filteredChats.isEmpty) {
                  return _EmptyState(
                    icon: Icons.chat_bubble_outline,
                    title: _searchQuery.isNotEmpty
                        ? 'No chats found'
                        : 'No conversations yet',
                    subtitle: _searchQuery.isNotEmpty
                        ? 'Try a different search term'
                        : 'Start a conversation with your team',
                    action: _searchQuery.isEmpty
                        ? TextButton.icon(
                            onPressed: () => _startNewDirectChat(context),
                            icon: const Icon(Icons.add),
                            label: const Text('Start Chat'),
                          )
                        : null,
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    return ref.refresh(userChatsProvider(userId));
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: filteredChats.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (context, index) {
                      final chat = filteredChats[index];
                      return _ChatListItem(
                        chat: chat,
                        currentUserId: userId,
                        onTap: () => _openChat(context, chat),
                        onLongPress: () => _showChatOptions(context, chat),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: AppColors.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load chats',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error.toString(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        ref.invalidate(userChatsProvider(userId));
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _startNewDirectChat(context),
        backgroundColor: AppColors.defaultBlue,
        child: const Icon(Icons.chat, color: Colors.white),
      ),
    );
  }

  String _getFilterDisplayName(String filter) {
    switch (filter) {
      case 'all':
        return 'All';
      case 'direct':
        return 'Direct';
      case 'group':
        return 'Groups';
      case 'team':
        return 'Teams';
      case 'department':
        return 'Departments';
      default:
        return filter;
    }
  }

  List<ChatModel> _filterChats(List<ChatModel> chats) {
    var filteredChats = chats;

    // Apply type filter
    if (_selectedFilter != 'all') {
      filteredChats = filteredChats
          .where((chat) => chat.type == _selectedFilter)
          .toList();
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filteredChats = filteredChats.where((chat) {
        return chat.name.toLowerCase().contains(_searchQuery) ||
            (chat.lastMessage?.content.toLowerCase().contains(_searchQuery) ??
                false);
      }).toList();
    }

    return filteredChats;
  }

  void _showSearchDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search Chats'),
        content: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search messages and chat names...',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _searchController.clear();
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _openChat(BuildContext context, ChatModel chat) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatConversationScreen(chat: chat),
      ),
    );
  }

  void _showChatOptions(BuildContext context, ChatModel chat) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _ChatOptionsSheet(chat: chat),
    );
  }

  void _startNewDirectChat(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NewChatScreen()),
    );
  }
}

class _ChatListItem extends StatelessWidget {
  final ChatModel chat;
  final String currentUserId;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ChatListItem({
    required this.chat,
    required this.currentUserId,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastMessage = chat.lastMessage;
    final hasUnread = chat.hasUnread;

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: _buildAvatar(),
      title: Row(
        children: [
          Expanded(
            child: Text(
              _getChatDisplayName(),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: hasUnread ? FontWeight.bold : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (chat.isMuted)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.volume_off,
                size: 16,
                color: AppColors.onSurfaceVariant,
              ),
            ),
        ],
      ),
      subtitle: lastMessage != null
          ? Row(
              children: [
                if (lastMessage.senderId == currentUserId)
                  const Icon(
                    Icons.done,
                    size: 14,
                    color: AppColors.onSurfaceVariant,
                  ),
                Expanded(
                  child: Text(
                    lastMessage.isDeleted
                        ? 'This message was deleted'
                        : _getLastMessagePreview(lastMessage),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hasUnread
                          ? theme.colorScheme.onSurface
                          : AppColors.onSurfaceVariant,
                      fontWeight: hasUnread
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          : Text(
              _getChatTypeDescription(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (lastMessage != null)
            Text(
              _formatTimestamp(lastMessage.timestamp),
              style: theme.textTheme.labelSmall?.copyWith(
                color: hasUnread
                    ? AppColors.defaultBlue
                    : AppColors.onSurfaceVariant,
                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          if (hasUnread) ...[
            const SizedBox(height: 4),
            Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: AppColors.defaultBlue,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  chat.unreadCount > 99 ? '99+' : chat.unreadCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    if (chat.avatarUrl != null) {
      return CircleAvatar(
        radius: 24,
        backgroundImage: NetworkImage(chat.avatarUrl!),
        backgroundColor: AppColors.gray200,
      );
    }

    return CircleAvatar(
      radius: 24,
      backgroundColor: _getChatColor(),
      child: Icon(_getChatIcon(), color: Colors.white, size: 20),
    );
  }

  String _getChatDisplayName() {
    if (chat.isDirect) {
      // For direct chats, show the other participant's name
      final otherParticipant = chat.participants.firstWhere(
        (id) => id != currentUserId,
        orElse: () => '',
      );
      return otherParticipant.isNotEmpty ? otherParticipant : chat.name;
    }
    return chat.name;
  }

  String _getChatTypeDescription() {
    switch (chat.type) {
      case 'direct':
        return 'Direct message';
      case 'group':
        return '${chat.participants.length} members';
      case 'team':
        return 'Team chat • ${chat.participants.length} members';
      case 'department':
        return 'Department chat • ${chat.participants.length} members';
      default:
        return '';
    }
  }

  Color _getChatColor() {
    switch (chat.type) {
      case 'direct':
        return AppColors.defaultBlue;
      case 'group':
        return AppColors.green9;
      case 'team':
        return AppColors.purple9;
      case 'department':
        return AppColors.orange9;
      default:
        return AppColors.gray400;
    }
  }

  IconData _getChatIcon() {
    switch (chat.type) {
      case 'direct':
        return Icons.person;
      case 'group':
        return Icons.group;
      case 'team':
        return Icons.groups;
      case 'department':
        return Icons.business;
      default:
        return Icons.chat;
    }
  }

  String _getLastMessagePreview(ChatMessageModel message) {
    switch (message.type) {
      case 'text':
        return message.content;
      case 'image':
        return '📷 Image';
      case 'file':
        return '📎 ${message.attachments.isNotEmpty ? message.attachments.first : 'File'}';
      case 'system':
        return message.content;
      case 'product':
        final productName =
            message.metadata['product_name'] as String? ?? 'Product';
        final hasMessage = message.content.isNotEmpty;
        return hasMessage
            ? '🛍️ $productName: ${message.content}'
            : '🛍️ Shared $productName';
      default:
        return message.content;
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m';
    } else if (difference.inDays < 1) {
      return DateFormat('HH:mm').format(timestamp);
    } else if (difference.inDays < 7) {
      return DateFormat('EEE').format(timestamp);
    } else {
      return DateFormat('MM/dd').format(timestamp);
    }
  }
}

class _ChatOptionsSheet extends ConsumerWidget {
  final ChatModel chat;

  const _ChatOptionsSheet({required this.chat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.gray300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          ListTile(
            leading: Icon(
              chat.isMuted ? Icons.volume_up : Icons.volume_off,
              color: AppColors.onSurfaceVariant,
            ),
            title: Text(chat.isMuted ? 'Unmute' : 'Mute'),
            onTap: () async {
              Navigator.pop(context);
              try {
                final chatService = ref.read(chatServiceProvider);
                await chatService.muteChat(chat.id, !chat.isMuted);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        chat.isMuted ? 'Chat unmuted' : 'Chat muted',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Failed to ${chat.isMuted ? 'unmute' : 'mute'} chat',
                      ),
                    ),
                  );
                }
              }
            },
          ),

          if (chat.isGroup || chat.isTeam || chat.isDepartment)
            ListTile(
              leading: const Icon(
                Icons.info_outline,
                color: AppColors.onSurfaceVariant,
              ),
              title: const Text('Chat Info'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ChatInfoScreen(chat: chat),
                  ),
                );
              },
            ),

          ListTile(
            leading: const Icon(
              Icons.search,
              color: AppColors.onSurfaceVariant,
            ),
            title: const Text('Search Messages'),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => MessageSearchScreen(chat: chat),
                ),
              );
            },
          ),

          const Divider(),

          if (!chat.isDepartment && !chat.isTeam)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('Delete Chat'),
              textColor: AppColors.error,
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirmation(context, chat);
              },
            ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, ChatModel chat) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Chat'),
        content: const Text(
          'Are you sure you want to delete this chat? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final chatService = ChatService();
                await chatService.deleteChat(chat.id);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Chat deleted successfully')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete chat: $e')),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}
