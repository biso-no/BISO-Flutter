import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/chat_model.dart';
import '../../../providers/auth/auth_provider.dart';
import 'chat_list_screen.dart';
import 'user_picker_screen.dart';

class ChatInfoScreen extends ConsumerStatefulWidget {
  final ChatModel chat;

  const ChatInfoScreen({super.key, required this.chat});

  @override
  ConsumerState<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends ConsumerState<ChatInfoScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  bool _isEditing = false;
  Map<String, String> _userNames = {};

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.chat.name;
    _descriptionController.text = widget.chat.description ?? '';
    _loadUserNames();
  }

  Future<void> _loadUserNames() async {
    try {
      final chatService = ref.read(chatServiceProvider);
      final userNames = await chatService.getUserNames(
        widget.chat.participants,
      );
      setState(() {
        _userNames = userNames;
      });
    } catch (e) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final currentUserId = authState.user?.id ?? '';
    final isOwner = widget.chat.metadata['created_by'] == currentUserId;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Chat Info'),
        actions: [
          if ((widget.chat.isGroup || widget.chat.isTeam) && isOwner)
            IconButton(
              onPressed: () => setState(() => _isEditing = !_isEditing),
              icon: Icon(_isEditing ? Icons.check : Icons.edit),
            ),
        ],
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Chat Avatar and Name
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: AppColors.subtleBlue,
                    backgroundImage: widget.chat.avatarUrl != null
                        ? NetworkImage(widget.chat.avatarUrl!)
                        : null,
                    child: widget.chat.avatarUrl == null
                        ? Icon(
                            _getChatIcon(),
                            size: 40,
                            color: AppColors.defaultBlue,
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),

                  if (_isEditing)
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Chat Name',
                        border: OutlineInputBorder(),
                      ),
                    )
                  else
                    Text(
                      widget.chat.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Chat Type
            _InfoSection(
              title: 'Type',
              child: Text(
                _getChatTypeDisplay(),
                style: const TextStyle(fontSize: 16),
              ),
            ),

            const SizedBox(height: 16),

            // Description
            if (widget.chat.description != null || _isEditing)
              _InfoSection(
                title: 'Description',
                child: _isEditing
                    ? TextField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      )
                    : Text(
                        widget.chat.description ?? 'No description',
                        style: const TextStyle(fontSize: 16),
                      ),
              ),

            const SizedBox(height: 16),

            // Participants
            _InfoSection(
              title: 'Participants (${widget.chat.participants.length})',
              child: Column(
                children: widget.chat.participants.map((participantId) {
                  final isCurrentUser = participantId == currentUserId;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: AppColors.subtleBlue,
                      child: Text(
                        participantId.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.defaultBlue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      isCurrentUser
                          ? 'You'
                          : (_userNames[participantId] ?? 'Loading...'),
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      _getUserRole(participantId),
                      style: const TextStyle(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    trailing: isOwner && !isCurrentUser
                        ? IconButton(
                            icon: const Icon(Icons.more_vert),
                            onPressed: () =>
                                _showParticipantOptions(participantId),
                          )
                        : null,
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 16),

            // Chat Stats
            _InfoSection(
              title: 'Chat Statistics',
              child: Column(
                children: [
                  _StatRow('Created', _formatDate(widget.chat.createdAt)),
                  _StatRow(
                    'Last Activity',
                    _formatDate(widget.chat.lastActivityAt),
                  ),
                  _StatRow(
                    'Messages',
                    widget.chat.metadata['message_count']?.toString() ?? '0',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Actions
            if (widget.chat.isGroup || widget.chat.isTeam)
              Column(
                children: [
                  if (!isOwner)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _leaveChat,
                        icon: const Icon(
                          Icons.exit_to_app,
                          color: AppColors.error,
                        ),
                        label: const Text(
                          'Leave Chat',
                          style: TextStyle(color: AppColors.error),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.error),
                        ),
                      ),
                    ),

                  if (isOwner) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _addParticipant,
                        icon: const Icon(Icons.person_add),
                        label: const Text('Add Participant'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _deleteChat,
                        icon: const Icon(Icons.delete, color: AppColors.error),
                        label: const Text(
                          'Delete Chat',
                          style: TextStyle(color: AppColors.error),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.error),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  IconData _getChatIcon() {
    switch (widget.chat.type) {
      case 'direct':
        return Icons.person;
      case 'group':
        return Icons.group;
      case 'team':
        return Icons.business;
      case 'department':
        return Icons.domain;
      default:
        return Icons.chat;
    }
  }

  String _getChatTypeDisplay() {
    switch (widget.chat.type) {
      case 'direct':
        return 'Direct Message';
      case 'group':
        return 'Group Chat';
      case 'team':
        return 'Team Chat';
      case 'department':
        return 'Department Chat';
      default:
        return 'Chat';
    }
  }

  String _getUserRole(String userId) {
    final currentUserId = ref.read(authStateProvider).user?.id ?? '';
    if (widget.chat.metadata['created_by'] == userId) {
      return 'Owner';
    } else if (userId == currentUserId) {
      return 'You';
    } else {
      return 'Member';
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showParticipantOptions(String participantId) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.person_remove, color: AppColors.error),
            title: const Text('Remove from chat'),
            onTap: () {
              Navigator.of(context).pop();
              _removeParticipant(participantId);
            },
          ),
          ListTile(
            leading: const Icon(Icons.cancel),
            title: const Text('Cancel'),
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  void _leaveChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Chat'),
        content: const Text('Are you sure you want to leave this chat?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final chatService = ref.read(chatServiceProvider);
        final currentUserId = ref.read(authStateProvider).user!.id;
        await chatService.removeUserFromChat(widget.chat.id, currentUserId);

        if (mounted) {
          context.pop(); // Go back to chat list
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Left chat successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to leave chat: $e')));
        }
      }
    }
  }

  void _removeParticipant(String participantId) async {
    try {
      final chatService = ref.read(chatServiceProvider);
      await chatService.removeUserFromChat(widget.chat.id, participantId);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Participant removed')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove participant: $e')),
        );
      }
    }
  }

  void _addParticipant() async {
    final selectedUserIds = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (context) => UserPickerScreen(
          excludeUserIds: widget.chat.participants,
          title: 'Add Participants',
          multiSelect: true,
        ),
      ),
    );

    if (selectedUserIds != null && selectedUserIds.isNotEmpty) {
      try {
        final chatService = ref.read(chatServiceProvider);

        // Add each selected user to the chat
        for (final userId in selectedUserIds) {
          await chatService.addUserToChat(widget.chat.id, userId);
        }

        // Reload user names to include new participants
        await _loadUserNames();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added ${selectedUserIds.length} participant(s)'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to add participants: $e')),
          );
        }
      }
    }
  }

  void _deleteChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Chat'),
        content: const Text(
          'Are you sure you want to delete this chat? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final chatService = ref.read(chatServiceProvider);
        await chatService.deleteChat(widget.chat.id);

        if (mounted) {
          context.pop(); // Go back to chat list
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chat deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to delete chat: $e')));
        }
      }
    }
  }
}

class _InfoSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _InfoSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.defaultBlue,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          Text(value),
        ],
      ),
    );
  }
}
