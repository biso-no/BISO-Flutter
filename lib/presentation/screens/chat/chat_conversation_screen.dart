import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/biso_chrome.dart';
import '../../../data/models/chat_model.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../widgets/biso/biso.dart';
import 'chat_list_screen.dart';
import 'chat_info_screen.dart';

final chatMessagesProvider =
    StreamProvider.family<List<ChatMessageModel>, String>((ref, chatId) {
      final chatService = ref.read(chatServiceProvider);
      return chatService.messagesStream;
    });

class ChatConversationScreen extends ConsumerStatefulWidget {
  final ChatModel chat;
  final String? scrollToMessageId;

  const ChatConversationScreen({
    super.key,
    required this.chat,
    this.scrollToMessageId,
  });

  @override
  ConsumerState<ChatConversationScreen> createState() =>
      _ChatConversationScreenState();
}

class _ChatConversationScreenState
    extends ConsumerState<ChatConversationScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();

  bool _isTyping = false;
  bool _isSending = false;
  ChatMessageModel? _replyingTo;
  ChatMessageModel? _editingMessage;
  final List<File> _attachments = [];

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onMessageChanged);

    // Mark chat as read when entering
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markAsRead();

      // Scroll to specific message if provided
      if (widget.scrollToMessageId != null) {
        _scrollToMessage(widget.scrollToMessageId!);
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  void _onMessageChanged() {
    final hasText = _messageController.text.trim().isNotEmpty;
    if (hasText != _isTyping) {
      setState(() {
        _isTyping = hasText;
      });

      final chatService = ref.read(chatServiceProvider);
      final currentUserId = ref.read(authStateProvider).user!.id;
      final userName = ref.read(authStateProvider).user?.name ?? 'Unknown';
      chatService.sendTypingIndicator(
        widget.chat.id,
        currentUserId,
        userName,
        hasText,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final messagesAsync = ref.watch(chatMessagesProvider(widget.chat.id));

    if (authState.user == null) {
      return const BisoPage(
        largeTitle: false,
        slivers: [SliverToBoxAdapter(child: BisoSkeleton.rows())],
      );
    }

    final palette = BisoPalette.of(context);
    final displayName = _getChatDisplayName(authState.user!.id);
    // The old AppBar showed the chat name and, for group/team/department
    // chats, a "N members" line underneath. BisoPage's title is a single
    // line, so both are folded into one string rather than dropped.
    final title =
        (widget.chat.isGroup || widget.chat.isTeam || widget.chat.isDepartment)
        ? '$displayName · ${widget.chat.participants.length} members'
        : displayName;

    return BisoPage(
      title: title,
      largeTitle: false,
      actions: [
        BisoHeaderAction(
          icon: CupertinoIcons.info_circle,
          tooltip: 'Chat info',
          onPressed: _showChatInfo,
        ),
      ],
      body: messagesAsync.when(
        data: (messages) {
          if (messages.isEmpty) {
            return Padding(
              padding: BisoPageInsets.padding(context),
              child: _buildEmptyState(context),
            );
          }

          return ListView.builder(
            controller: _scrollController,
            reverse: true,
            padding: BisoPageInsets.padding(
              context,
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              final previousMessage = index < messages.length - 1
                  ? messages[index + 1]
                  : null;
              final showDateSeparator = _shouldShowDateSeparator(
                message,
                previousMessage,
              );
              final showAvatar = _shouldShowAvatar(message, previousMessage);

              return Column(
                children: [
                  if (showDateSeparator) _DateSeparator(date: message.timestamp),

                  _MessageBubble(
                    message: message,
                    currentUserId: authState.user!.id,
                    showAvatar: showAvatar,
                    onReply: () => _setReplyingTo(message),
                    onEdit: () => _setEditingMessage(message),
                    onDelete: () => _deleteMessage(message),
                    onReact: (emoji) => _reactToMessage(message, emoji),
                  ),
                ],
              );
            },
          );
        },
        loading: () => Padding(
          padding: BisoPageInsets.padding(context),
          child: const Center(child: CircularProgressIndicator()),
        ),
        error: (error, stack) => Padding(
          padding: BisoPageInsets.padding(context),
          child: BisoErrorState(
            message: 'Failed to load messages: ${error.toString()}',
            onRetry: () => ref.refresh(chatMessagesProvider(widget.chat.id)),
          ),
        ),
      ),
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyingTo != null)
            _ReplyBanner(message: _replyingTo!, onCancel: () => _cancelReply()),

          if (_editingMessage != null)
            _EditBanner(
              message: _editingMessage!,
              onCancel: () => _cancelEdit(),
            ),

          if (_attachments.isNotEmpty)
            _AttachmentsPreview(
              attachments: _attachments,
              onRemove: _removeAttachment,
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: BisoChrome(
              radius: 26,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: _showAttachmentOptions,
                    icon: Icon(CupertinoIcons.paperclip, color: palette.muted),
                  ),

                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: TextField(
                        controller: _messageController,
                        focusNode: _messageFocusNode,
                        maxLines: null,
                        textInputAction: TextInputAction.newline,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.copyWith(color: palette.ink),
                        decoration: bisoInputDecoration(
                          context,
                          hintText: _getInputHint(),
                        ),
                      ),
                    ),
                  ),

                  IconButton(
                    onPressed: _canSendMessage() ? _sendMessage : null,
                    icon: _isSending
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: palette.link,
                            ),
                          )
                        : Icon(
                            CupertinoIcons.paperplane_fill,
                            color: _canSendMessage()
                                ? palette.link
                                : palette.muted,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return BisoEmptyState(
      icon: widget.chat.isDirect
          ? CupertinoIcons.chat_bubble
          : CupertinoIcons.person_2,
      accent: BisoAccent.teal,
      title: widget.chat.isDirect
          ? 'Start your conversation'
          : 'Welcome to ${widget.chat.name}',
      message: widget.chat.isDirect
          ? 'Send a message to get started'
          : 'Be the first to send a message',
    );
  }

  String _getChatDisplayName(String currentUserId) {
    if (widget.chat.isDirect) {
      final otherParticipant = widget.chat.participants.firstWhere(
        (id) => id != currentUserId,
        orElse: () => '',
      );
      return otherParticipant.isNotEmpty ? otherParticipant : widget.chat.name;
    }
    return widget.chat.name;
  }

  String _getInputHint() {
    if (_editingMessage != null) {
      return 'Edit message...';
    } else if (_replyingTo != null) {
      return 'Reply...';
    } else {
      return 'Type a message...';
    }
  }

  bool _shouldShowDateSeparator(
    ChatMessageModel message,
    ChatMessageModel? previousMessage,
  ) {
    if (previousMessage == null) return true;

    final messageDate = DateTime(
      message.timestamp.year,
      message.timestamp.month,
      message.timestamp.day,
    );
    final previousDate = DateTime(
      previousMessage.timestamp.year,
      previousMessage.timestamp.month,
      previousMessage.timestamp.day,
    );

    return !messageDate.isAtSameMomentAs(previousDate);
  }

  bool _shouldShowAvatar(
    ChatMessageModel message,
    ChatMessageModel? previousMessage,
  ) {
    if (previousMessage == null) return true;
    if (previousMessage.senderId != message.senderId) return true;

    final timeDifference = message.timestamp.difference(
      previousMessage.timestamp,
    );
    return timeDifference.inMinutes > 5;
  }

  bool _canSendMessage() {
    return (_messageController.text.trim().isNotEmpty ||
            _attachments.isNotEmpty) &&
        !_isSending;
  }

  void _setReplyingTo(ChatMessageModel message) {
    setState(() {
      _replyingTo = message;
      _editingMessage = null;
    });
    _messageFocusNode.requestFocus();
  }

  void _setEditingMessage(ChatMessageModel message) {
    setState(() {
      _editingMessage = message;
      _replyingTo = null;
      _messageController.text = message.content;
    });
    _messageFocusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyingTo = null;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingMessage = null;
      _messageController.clear();
    });
  }

  Future<void> _sendMessage() async {
    if (!_canSendMessage() || _isSending) return;

    final content = _messageController.text.trim();
    final chatService = ref.read(chatServiceProvider);
    final currentUserId = ref.read(authStateProvider).user!.id;

    setState(() {
      _isSending = true;
    });

    try {
      if (_editingMessage != null) {
        // Edit existing message
        await chatService.editMessage(
          messageId: _editingMessage!.id,
          newContent: content,
        );
        _cancelEdit();
      } else {
        // Handle file attachments separately
        if (_attachments.isNotEmpty) {
          // Send each file as a separate message
          for (final attachment in _attachments) {
            final fileName = attachment.path.split('/').last;
            await chatService.sendFileMessage(
              chatId: widget.chat.id,
              senderId: currentUserId,
              senderName: ref.read(authStateProvider).user?.name ?? 'Unknown',
              file: attachment,
              fileName: fileName,
              caption: content.isNotEmpty ? content : null,
              replyToId: _replyingTo?.id,
            );
          }
        } else {
          // Send text message
          await chatService.sendMessage(
            chatId: widget.chat.id,
            senderId: currentUserId,
            senderName: ref.read(authStateProvider).user?.name ?? 'Unknown',
            content: content,
            type: 'text',
            replyToId: _replyingTo?.id,
          );
        }

        _messageController.clear();
        _cancelReply();
        setState(() {
          _attachments.clear();
        });

        // Scroll to bottom
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _deleteMessage(ChatMessageModel message) async {
    final palette = BisoPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: palette.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final chatService = ref.read(chatServiceProvider);
        await chatService.deleteMessage(message.id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete message: ${e.toString()}'),
            ),
          );
        }
      }
    }
  }

  Future<void> _reactToMessage(ChatMessageModel message, String emoji) async {
    try {
      final chatService = ref.read(chatServiceProvider);
      final currentUserId = ref.read(authStateProvider).user!.id;

      await chatService.reactToMessage(
        messageId: message.id,
        userId: currentUserId,
        userName: ref.read(authStateProvider).user?.name ?? 'Unknown',
        reaction: emoji,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to react: ${e.toString()}')),
        );
      }
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final palette = BisoPalette.of(sheetContext);
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: BisoListGroup(
                children: [
                  BisoListRow(
                    title: 'Camera',
                    leading: Icon(CupertinoIcons.camera, color: palette.link),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _pickImage(ImageSource.camera);
                    },
                  ),
                  BisoListRow(
                    title: 'Photo Gallery',
                    leading: Icon(CupertinoIcons.photo, color: palette.muted),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _pickImage(ImageSource.gallery);
                    },
                  ),
                  BisoListRow(
                    title: 'Document',
                    leading: Icon(
                      CupertinoIcons.paperclip,
                      color: palette.muted,
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _pickFile();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: source);

      if (image != null) {
        setState(() {
          _attachments.add(File(image.path));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles();

      if (result != null && result.files.single.path != null) {
        setState(() {
          _attachments.add(File(result.files.single.path!));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick file: ${e.toString()}')),
        );
      }
    }
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments.removeAt(index);
    });
  }

  void _markAsRead() {
    try {
      final chatService = ref.read(chatServiceProvider);
      final currentUserId = ref.read(authStateProvider).user!.id;
      chatService.markChatAsRead(widget.chat.id, currentUserId);
    } catch (e) {
      // Silently fail - not critical
    }
  }

  void _scrollToMessage(String messageId) {
    // Wait for messages to load, then scroll to the specific message
    Future.delayed(const Duration(milliseconds: 500), () {
      final messagesAsync = ref.read(chatMessagesProvider(widget.chat.id));
      messagesAsync.whenData((messages) {
        final messageIndex = messages.indexWhere((msg) => msg.id == messageId);
        if (messageIndex != -1 && _scrollController.hasClients) {
          // Calculate approximate position (each message is roughly 60px high)
          final position = messageIndex * 60.0;
          _scrollController.animateTo(
            position,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );

          // Highlight the message briefly
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Message found'),
                  duration: Duration(seconds: 1),
                ),
              );
            }
          });
        }
      });
    });
  }

  void _showChatInfo() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChatInfoScreen(chat: widget.chat),
      ),
    );
  }
}

// Message bubble widget
class _MessageBubble extends StatelessWidget {
  final ChatMessageModel message;
  final String currentUserId;
  final bool showAvatar;
  final VoidCallback onReply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Function(String) onReact;

  const _MessageBubble({
    required this.message,
    required this.currentUserId,
    required this.showAvatar,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onReact,
  });

  bool get isMe => message.senderId == currentUserId;

  @override
  Widget build(BuildContext context) {
    if (message.isDeleted) {
      return _buildDeletedMessage(context);
    }

    if (message.type == 'system') {
      return _buildSystemMessage(context);
    }

    if (message.type == 'product') {
      return _buildProductMessage(context);
    }

    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    final bubbleColor = isMe ? palette.primary : palette.surface;
    final contentColor = isMe ? palette.onPrimary : palette.ink;
    final timeColor = isMe
        ? palette.onPrimary.withValues(alpha: 0.7)
        : palette.muted;

    return Container(
      margin: EdgeInsets.symmetric(
        vertical: showAvatar ? 8 : 2,
        horizontal: 4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe && showAvatar)
            _buildAvatar(context)
          else if (!isMe)
            const SizedBox(width: 40),

          if (!isMe) const SizedBox(width: 8),

          Expanded(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isMe && showAvatar)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 4),
                    child: Text(
                      message.senderName,
                      style: text.labelMedium?.copyWith(color: palette.muted),
                    ),
                  ),

                GestureDetector(
                  onLongPress: () => _showMessageOptions(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft: Radius.circular(isMe ? 20 : 6),
                        bottomRight: Radius.circular(isMe ? 6 : 20),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message.replyTo != null)
                          _buildReplyPreview(context, contentColor),

                        if (message.isEdited)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              'edited',
                              style: text.labelSmall?.copyWith(
                                color: contentColor.withValues(alpha: 0.7),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),

                        Text(
                          message.content,
                          style: text.bodyLarge?.copyWith(color: contentColor),
                        ),

                        if (message.attachments.isNotEmpty)
                          _buildAttachments(context, contentColor),

                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: Text(
                              _formatTime(message.timestamp),
                              style: text.labelSmall?.copyWith(
                                color: timeColor,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (message.reactions.isNotEmpty) _buildReactions(context),
              ],
            ),
          ),

          if (isMe) const SizedBox(width: 8),

          if (isMe && showAvatar)
            _buildAvatar(context)
          else if (isMe)
            const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildDeletedMessage(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(
        children: [
          const SizedBox(width: 48), // Avatar space
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: palette.surfaceRaised,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(CupertinoIcons.trash, size: 16, color: palette.muted),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'This message was deleted',
                      style: text.bodyMedium?.copyWith(
                        color: palette.muted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductMessage(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    final productName =
        message.metadata['product_name'] as String? ?? 'Product';
    final productPrice = message.metadata['product_price'] as double? ?? 0.0;
    final productImage = message.metadata['product_image'] as String? ?? '';
    final bubbleColor = isMe ? palette.primary : palette.surface;
    final contentColor = isMe ? palette.onPrimary : palette.ink;
    final cardColor = isMe
        ? palette.onPrimary.withValues(alpha: 0.12)
        : palette.surfaceRaised;
    final timeColor = isMe
        ? palette.onPrimary.withValues(alpha: 0.7)
        : palette.muted;

    return Container(
      margin: EdgeInsets.symmetric(
        vertical: showAvatar ? 8 : 2,
        horizontal: 4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe && showAvatar)
            _buildAvatar(context)
          else if (!isMe)
            const SizedBox(width: 40),

          if (!isMe) const SizedBox(width: 8),

          Expanded(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isMe && showAvatar)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 4),
                    child: Text(
                      message.senderName,
                      style: text.labelMedium?.copyWith(color: palette.muted),
                    ),
                  ),

                Container(
                  constraints: const BoxConstraints(maxWidth: 300),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isMe ? 20 : 6),
                      bottomRight: Radius.circular(isMe ? 6 : 20),
                    ),
                    border: !isMe ? Border.all(color: palette.hairline) : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: productImage.isNotEmpty
                                    ? Image.network(
                                        productImage,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Container(
                                          color: palette.surfaceRaised,
                                          child: Icon(
                                            CupertinoIcons.bag_fill,
                                            color: palette.muted,
                                          ),
                                        ),
                                      )
                                    : Container(
                                        color: palette.surfaceRaised,
                                        child: Icon(
                                          CupertinoIcons.bag_fill,
                                          color: palette.muted,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    productName,
                                    style: text.labelLarge?.copyWith(
                                      color: contentColor,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'NOK ${productPrice.toStringAsFixed(0)}',
                                    style: text.titleMedium?.copyWith(
                                      color: isMe ? contentColor : palette.link,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // User message
                      if (message.content.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            message.content,
                            style: text.bodyLarge?.copyWith(
                              color: contentColor,
                            ),
                          ),
                        ),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Align(
                          alignment: Alignment.bottomRight,
                          child: Text(
                            _formatTime(message.timestamp),
                            style: text.labelSmall?.copyWith(
                              color: timeColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (message.reactions.isNotEmpty) _buildReactions(context),
              ],
            ),
          ),

          if (isMe) const SizedBox(width: 8),

          if (isMe && showAvatar)
            _buildAvatar(context)
          else if (isMe)
            const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildSystemMessage(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message.content,
            style: text.labelSmall?.copyWith(color: palette.muted),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final palette = BisoPalette.of(context);
    return CircleAvatar(
      radius: 16,
      backgroundImage: message.senderAvatar != null
          ? NetworkImage(message.senderAvatar!)
          : null,
      backgroundColor: palette.surfaceRaised,
      child: message.senderAvatar == null
          ? Text(
              (message.senderName.isNotEmpty
                      ? message.senderName[0]
                      : message.senderId[0])
                  .toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: palette.ink,
              ),
            )
          : null,
    );
  }

  Widget _buildReplyPreview(BuildContext context, Color contentColor) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: palette.link, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.replyTo!.senderName,
            style: text.labelMedium?.copyWith(color: palette.link),
          ),
          const SizedBox(height: 2),
          Text(
            message.replyTo!.content,
            style: text.labelSmall?.copyWith(
              color: contentColor.withValues(alpha: 0.8),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildAttachments(BuildContext context, Color contentColor) {
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: Column(
        children: message.attachments.map((attachment) {
          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(CupertinoIcons.doc_text, size: 16, color: contentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    attachment,
                    style: text.labelSmall?.copyWith(color: contentColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildReactions(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        children: message.reactions.entries.map((entry) {
          final emoji = entry.key;
          final users = entry.value;
          final mine = users.contains(currentUserId);

          return GestureDetector(
            onTap: () => onReact(emoji),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: palette.surfaceRaised,
                borderRadius: BorderRadius.circular(12),
                border: mine
                    ? Border.all(color: palette.link, width: 1)
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 12)),
                  if (users.length > 1) ...[
                    const SizedBox(width: 2),
                    Text(
                      users.length.toString(),
                      style: text.labelSmall?.copyWith(color: palette.muted),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showMessageOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final palette = BisoPalette.of(sheetContext);
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: BisoListGroup(
                children: [
                  BisoListRow(
                    title: 'Reply',
                    leading: Icon(CupertinoIcons.reply, color: palette.link),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onReply();
                    },
                  ),
                  BisoListRow(
                    title: 'React',
                    leading: Icon(CupertinoIcons.smiley, color: palette.muted),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showReactionPicker(context);
                    },
                  ),
                  if (isMe) ...[
                    BisoListRow(
                      title: 'Edit',
                      leading: Icon(
                        CupertinoIcons.pencil,
                        color: palette.muted,
                      ),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        onEdit();
                      },
                    ),
                    BisoListRow(
                      title: 'Delete',
                      destructive: true,
                      leading: Icon(
                        CupertinoIcons.trash,
                        color: palette.error,
                      ),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        onDelete();
                      },
                    ),
                  ],
                  BisoListRow(
                    title: 'Copy',
                    leading: Icon(
                      CupertinoIcons.doc_on_doc,
                      color: palette.muted,
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      Clipboard.setData(ClipboardData(text: message.content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showReactionPicker(BuildContext context) {
    final reactions = ['👍', '❤️', '😂', '😮', '😢', '😡'];

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final palette = BisoPalette.of(sheetContext);
        final text = Theme.of(sheetContext).textTheme;
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'React to message',
                    style: text.titleMedium?.copyWith(color: palette.ink),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: reactions.map((emoji) {
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(sheetContext);
                          onReact(emoji);
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: palette.surfaceRaised,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Center(
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime timestamp) {
    return DateFormat('HH:mm').format(timestamp);
  }
}

// Date separator widget
class _DateSeparator extends StatelessWidget {
  final DateTime date;

  const _DateSeparator({required this.date});

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: palette.hairline)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _formatDate(date),
              style: text.labelSmall?.copyWith(
                color: palette.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Divider(color: palette.hairline)),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date).inDays;

    if (difference == 0) {
      return 'Today';
    } else if (difference == 1) {
      return 'Yesterday';
    } else if (difference < 7) {
      return DateFormat('EEEE').format(date);
    } else {
      return DateFormat('MMM d, yyyy').format(date);
    }
  }
}

// Reply banner widget
class _ReplyBanner extends StatelessWidget {
  final ChatMessageModel message;
  final VoidCallback onCancel;

  const _ReplyBanner({required this.message, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        border: Border(top: BorderSide(color: palette.hairline, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: palette.link,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to ${message.senderName}',
                  style: text.labelMedium?.copyWith(color: palette.link),
                ),
                const SizedBox(height: 2),
                Text(
                  message.content,
                  style: text.bodySmall?.copyWith(color: palette.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: Icon(CupertinoIcons.xmark, size: 20, color: palette.muted),
          ),
        ],
      ),
    );
  }
}

// Edit banner widget
class _EditBanner extends StatelessWidget {
  final ChatMessageModel message;
  final VoidCallback onCancel;

  const _EditBanner({required this.message, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        border: Border(top: BorderSide(color: palette.hairline, width: 0.5)),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.pencil, size: 16, color: palette.link),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Edit message',
              style: text.labelMedium?.copyWith(color: palette.link),
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: Icon(CupertinoIcons.xmark, size: 20, color: palette.muted),
          ),
        ],
      ),
    );
  }
}

// Attachments preview widget
class _AttachmentsPreview extends StatelessWidget {
  final List<File> attachments;
  final Function(int) onRemove;

  const _AttachmentsPreview({
    required this.attachments,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        border: Border(top: BorderSide(color: palette.hairline, width: 0.5)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final file = attachments[index];
          final isImage = _isImageFile(file.path);

          return Stack(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: isImage
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(file, fit: BoxFit.cover),
                      )
                    : Icon(CupertinoIcons.doc_text, color: palette.muted),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => onRemove(index),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: palette.error,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.xmark,
                      size: 14,
                      color: palette.onPrimary,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  bool _isImageFile(String path) {
    final extension = path.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(extension);
  }
}
