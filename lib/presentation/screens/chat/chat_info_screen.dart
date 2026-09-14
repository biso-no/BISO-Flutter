import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/chat_model.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../widgets/biso/biso.dart';
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
    final l10n = AppLocalizations.of(context)!;

    return BisoPage(
      title: 'Chat Info',
      largeTitle: false,
      actions: [
        if ((widget.chat.isGroup || widget.chat.isTeam) && isOwner)
          BisoHeaderAction(
            icon: _isEditing ? CupertinoIcons.checkmark : CupertinoIcons.pencil,
            tooltip: _isEditing ? l10n.saveChangesMessage : l10n.editChatMessage,
            onPressed: () => setState(() => _isEditing = !_isEditing),
          ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: Builder(
            builder: (context) {
              final palette = BisoPalette.of(context);
              final text = Theme.of(context).textTheme;
              final insets = BisoPageInsets.maybeOf(context);
              final scrollPadding = insets != null
                  ? EdgeInsets.fromLTRB(
                      20,
                      insets.top + 20,
                      20,
                      insets.bottom + 20,
                    )
                  : const EdgeInsets.all(20);
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: BisoAccent.teal.fill(context),
                            backgroundImage: widget.chat.avatarUrl != null
                                ? NetworkImage(widget.chat.avatarUrl!)
                                : null,
                            child: widget.chat.avatarUrl == null
                                ? Icon(
                                    _getChatIcon(),
                                    size: 36,
                                    color: BisoAccent.teal.glyph(context),
                                  )
                                : null,
                          ),
                          const SizedBox(height: 16),
                          if (!_isEditing)
                            Text(
                              widget.chat.name,
                              textAlign: TextAlign.center,
                              style: text.headlineMedium?.copyWith(
                                color: palette.ink,
                              ),
                            ),
                          if (!_isEditing && widget.chat.description != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              widget.chat.description!,
                              textAlign: TextAlign.center,
                              style: text.bodyMedium?.copyWith(
                                color: palette.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_isEditing) ...[
                      const SizedBox(height: 20),
                      BisoFormGroup(
                        title: l10n.chatDetailsMessage,
                        children: [
                          BisoFormRow(
                            label: 'Chat Name',
                            child: TextField(
                              controller: _nameController,
                              scrollPadding: scrollPadding,
                              decoration: bisoInputDecoration(context),
                            ),
                          ),
                          BisoFormRow(
                            label: 'Description',
                            child: TextField(
                              controller: _descriptionController,
                              maxLines: 3,
                              scrollPadding: scrollPadding,
                              decoration: bisoInputDecoration(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),

        // Type
        SliverToBoxAdapter(
          child: BisoSection(
            child: BisoListGroup(
              children: [
                BisoListRow(title: 'Type', value: _getChatTypeDisplay()),
              ],
            ),
          ),
        ),

        // Participants
        SliverToBoxAdapter(
          child: BisoSection(
            title: 'Participants (${widget.chat.participants.length})',
            child: BisoListGroup(
              children: [
                for (final participantId in widget.chat.participants)
                  _buildParticipantRow(
                    context,
                    participantId,
                    currentUserId,
                    isOwner,
                  ),
              ],
            ),
          ),
        ),

        // Chat Statistics
        SliverToBoxAdapter(
          child: BisoSection(
            title: 'Chat Statistics',
            child: BisoListGroup(
              children: [
                BisoListRow(
                  title: 'Created',
                  value: _formatDate(widget.chat.createdAt),
                ),
                BisoListRow(
                  title: 'Last Activity',
                  value: _formatDate(widget.chat.lastActivityAt),
                ),
                BisoListRow(
                  title: 'Messages',
                  // R11: a message count is a quantity that must never be
                  // ellipsized, so it renders as a non-flexible trailing
                  // Text rather than BisoListRow's Flexible `value:`.
                  trailing: Text(
                    widget.chat.metadata['message_count']?.toString() ?? '0',
                    maxLines: 1,
                    softWrap: false,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: BisoPalette.of(context).muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Actions
        if (widget.chat.isGroup || widget.chat.isTeam)
          SliverToBoxAdapter(
            child: BisoSection(
              child: BisoListGroup(
                children: [
                  if (!isOwner)
                    BisoListRow(
                      leading: const BisoIconTile(
                        icon: CupertinoIcons.square_arrow_right,
                      ),
                      title: 'Leave Chat',
                      destructive: true,
                      showChevron: false,
                      onTap: _leaveChat,
                    ),
                  if (isOwner) ...[
                    BisoListRow(
                      leading: const BisoIconTile(
                        icon: CupertinoIcons.person_add,
                        accent: BisoAccent.teal,
                      ),
                      title: 'Add Participant',
                      onTap: _addParticipant,
                    ),
                    BisoListRow(
                      leading: const BisoIconTile(icon: CupertinoIcons.trash),
                      title: 'Delete Chat',
                      destructive: true,
                      showChevron: false,
                      onTap: _deleteChat,
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildParticipantRow(
    BuildContext context,
    String participantId,
    String currentUserId,
    bool isOwner,
  ) {
    final isCurrentUser = participantId == currentUserId;
    return BisoListRow(
      leading: CircleAvatar(
        backgroundColor: BisoAccent.teal.fill(context),
        child: Text(
          participantId.substring(0, 1).toUpperCase(),
          style: TextStyle(
            color: BisoAccent.teal.glyph(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      title: isCurrentUser ? 'You' : (_userNames[participantId] ?? 'Loading...'),
      subtitle: _getUserRole(participantId),
      trailing: isOwner && !isCurrentUser
          ? IconButton(
              icon: Icon(
                CupertinoIcons.ellipsis,
                color: BisoPalette.of(context).muted,
              ),
              onPressed: () => _showParticipantOptions(participantId),
            )
          : null,
    );
  }

  IconData _getChatIcon() {
    switch (widget.chat.type) {
      case 'direct':
        return CupertinoIcons.person_fill;
      case 'group':
        return CupertinoIcons.person_2;
      case 'team':
        return CupertinoIcons.building_2_fill;
      case 'department':
        return CupertinoIcons.building_2_fill;
      default:
        return CupertinoIcons.bubble_left_fill;
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
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: BisoListGroup(
            children: [
              BisoListRow(
                leading: const BisoIconTile(
                  icon: CupertinoIcons.person_badge_minus,
                  accent: BisoAccent.coral,
                ),
                title: 'Remove from chat',
                destructive: true,
                showChevron: false,
                onTap: () {
                  Navigator.of(context).pop();
                  _removeParticipant(participantId);
                },
              ),
              BisoListRow(
                leading: const BisoIconTile(icon: CupertinoIcons.xmark),
                title: 'Cancel',
                showChevron: false,
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: BisoPalette.of(context).error,
            ),
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
