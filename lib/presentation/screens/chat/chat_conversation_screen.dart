import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/chat_model.dart';
import '../../../providers/auth/auth_provider.dart';
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getChatDisplayName(authState.user!.id),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (widget.chat.isGroup ||
                widget.chat.isTeam ||
                widget.chat.isDepartment)
              Text(
                '${widget.chat.participants.length} members',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _showChatInfo(),
            icon: const Icon(Icons.info_outline),
          ),
        ],
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 1,
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: messagesAsync.when(
              data: (messages) {
                if (messages.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
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
                    final showAvatar = _shouldShowAvatar(
                      message,
                      previousMessage,
                    );

                    return Column(
                      children: [
                        if (showDateSeparator)
                          _DateSeparator(date: message.timestamp),

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
                    Text('Failed to load messages: ${error.toString()}'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () =>
                          ref.refresh(chatMessagesProvider(widget.chat.id)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Reply banner
          if (_replyingTo != null)
            _ReplyBanner(message: _replyingTo!, onCancel: () => _cancelReply()),

          // Edit banner
          if (_editingMessage != null)
            _EditBanner(
              message: _editingMessage!,
              onCancel: () => _cancelEdit(),
            ),

          // Attachments preview
          if (_attachments.isNotEmpty)
            _AttachmentsPreview(
              attachments: _attachments,
              onRemove: _removeAttachment,
            ),

          // Message input
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: const Border(
                top: BorderSide(color: AppColors.outline, width: 0.5),
              ),
            ),
            child: SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Attachment button
                  IconButton(
                    onPressed: _showAttachmentOptions,
                    icon: const Icon(Icons.attach_file),
                    color: AppColors.onSurfaceVariant,
                  ),

                  // Message input
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: TextField(
                        controller: _messageController,
                        focusNode: _messageFocusNode,
                        maxLines: null,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: _getInputHint(),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: AppColors.gray100,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Send button
                  Container(
                    decoration: BoxDecoration(
                      color: _canSendMessage()
                          ? AppColors.defaultBlue
                          : AppColors.gray300,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: _canSendMessage() ? _sendMessage : null,
                      icon: _isSending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.white,
                              ),
                            )
                          : const Icon(Icons.send, color: AppColors.white),
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.chat.isDirect
                ? Icons.chat_bubble_outline
                : Icons.group_outlined,
            size: 64,
            color: AppColors.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            widget.chat.isDirect
                ? 'Start your conversation'
                : 'Welcome to ${widget.chat.name}',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            widget.chat.isDirect
                ? 'Send a message to get started'
                : 'Be the first to send a message',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
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
          SnackBar(
            content: Text('Failed to send message: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
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
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
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
              backgroundColor: AppColors.error,
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
          SnackBar(
            content: Text('Failed to react: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.photo_camera,
                color: AppColors.defaultBlue,
              ),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.green9),
              title: const Text('Photo Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file, color: AppColors.orange9),
              title: const Text('Document'),
              onTap: () {
                Navigator.pop(context);
                _pickFile();
              },
            ),
          ],
        ),
      ),
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
          SnackBar(
            content: Text('Failed to pick image: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
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
          SnackBar(
            content: Text('Failed to pick file: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
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
                SnackBar(
                  content: const Text('Message found'),
                  duration: const Duration(seconds: 1),
                  backgroundColor: AppColors.defaultBlue,
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

    return Container(
      margin: EdgeInsets.symmetric(
        vertical: showAvatar ? 8 : 2,
        horizontal: 16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe && showAvatar)
            _buildAvatar()
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
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      message.senderName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurfaceVariant,
                      ),
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
                      color: isMe ? AppColors.defaultBlue : AppColors.gray100,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isMe ? 16 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message.replyTo != null) _buildReplyPreview(),

                        if (message.isEdited)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 4),
                            child: Text(
                              'edited',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),

                        Text(
                          message.content,
                          style: TextStyle(
                            color: isMe ? Colors.white : AppColors.onSurface,
                            fontSize: 16,
                          ),
                        ),

                        if (message.attachments.isNotEmpty) _buildAttachments(),
                      ],
                    ),
                  ),
                ),

                if (message.reactions.isNotEmpty) _buildReactions(),

                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _formatTime(message.timestamp),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (isMe) const SizedBox(width: 8),

          if (isMe && showAvatar)
            _buildAvatar()
          else if (isMe)
            const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildDeletedMessage(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Row(
        children: [
          const SizedBox(width: 48), // Avatar space
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.gray100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: AppColors.onSurfaceVariant,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'This message was deleted',
                    style: TextStyle(
                      color: AppColors.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
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
    final productName =
        message.metadata['product_name'] as String? ?? 'Product';
    final productPrice = message.metadata['product_price'] as double? ?? 0.0;
    final productImage = message.metadata['product_image'] as String? ?? '';

    return Container(
      margin: EdgeInsets.symmetric(
        vertical: showAvatar ? 8 : 2,
        horizontal: 16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe && showAvatar)
            _buildAvatar()
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
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      message.senderName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),

                Container(
                  constraints: const BoxConstraints(maxWidth: 300),
                  decoration: BoxDecoration(
                    color: isMe ? AppColors.defaultBlue : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                    border: !isMe ? Border.all(color: AppColors.outline) : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Colors.white.withValues(alpha: 0.1)
                              : AppColors.gray50,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16),
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
                                          color: AppColors.gray200,
                                          child: const Icon(Icons.shopping_bag),
                                        ),
                                      )
                                    : Container(
                                        color: AppColors.gray200,
                                        child: const Icon(Icons.shopping_bag),
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
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: isMe
                                          ? Colors.white
                                          : AppColors.onSurface,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'NOK ${productPrice.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                      color: isMe
                                          ? Colors.white
                                          : AppColors.defaultBlue,
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
                            style: TextStyle(
                              color: isMe ? Colors.white : AppColors.onSurface,
                              fontSize: 16,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                if (message.reactions.isNotEmpty) _buildReactions(),

                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _formatTime(message.timestamp),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (isMe) const SizedBox(width: 8),

          if (isMe && showAvatar)
            _buildAvatar()
          else if (isMe)
            const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildSystemMessage(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.gray200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message.content,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return CircleAvatar(
      radius: 16,
      backgroundImage: message.senderAvatar != null
          ? NetworkImage(message.senderAvatar!)
          : null,
      backgroundColor: AppColors.gray300,
      child: message.senderAvatar == null
          ? Text(
              (message.senderName.isNotEmpty
                      ? message.senderName[0]
                      : message.senderId[0])
                  .toUpperCase(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            )
          : null,
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isMe ? Colors.white : AppColors.defaultBlue,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.replyTo!.senderName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isMe
                  ? Colors.white.withValues(alpha: 0.8)
                  : AppColors.defaultBlue,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            message.replyTo!.content,
            style: TextStyle(
              fontSize: 12,
              color: isMe
                  ? Colors.white.withValues(alpha: 0.7)
                  : AppColors.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildAttachments() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: Column(
        children: message.attachments.map((attachment) {
          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.attach_file, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    attachment,
                    style: const TextStyle(fontSize: 12),
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

  Widget _buildReactions() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        children: message.reactions.entries.map((entry) {
          final emoji = entry.key;
          final users = entry.value;

          return GestureDetector(
            onTap: () => onReact(emoji),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: users.contains(currentUserId)
                    ? AppColors.subtleBlue
                    : AppColors.gray200,
                borderRadius: BorderRadius.circular(12),
                border: users.contains(currentUserId)
                    ? Border.all(color: AppColors.defaultBlue, width: 1)
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
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurfaceVariant,
                      ),
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
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply, color: AppColors.defaultBlue),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                onReply();
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_reaction, color: AppColors.orange9),
              title: const Text('React'),
              onTap: () {
                Navigator.pop(context);
                _showReactionPicker(context);
              },
            ),
            if (isMe) ...[
              ListTile(
                leading: const Icon(Icons.edit, color: AppColors.green9),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(context);
                  onEdit();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: AppColors.error),
                title: const Text('Delete'),
                onTap: () {
                  Navigator.pop(context);
                  onDelete();
                },
              ),
            ],
            ListTile(
              leading: const Icon(
                Icons.copy,
                color: AppColors.onSurfaceVariant,
              ),
              title: const Text('Copy'),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: message.content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showReactionPicker(BuildContext context) {
    final reactions = ['👍', '❤️', '😂', '😮', '😢', '😡'];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'React to message',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: reactions.map((emoji) {
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    onReact(emoji);
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.gray100,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 24)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
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
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.gray200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _formatDate(date),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Expanded(child: Divider()),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.midNavy.withValues(alpha: 0.5)
            : AppColors.subtleBlue,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.outlineDark : AppColors.outline,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.defaultBlue,
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
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.defaultBlue,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message.content,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close, size: 20),
            color: AppColors.onSurfaceVariant,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.midNavy.withValues(alpha: 0.5)
            : AppColors.subtleBlue,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.outlineDark : AppColors.outline,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit, size: 16, color: AppColors.defaultBlue),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Edit message',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.defaultBlue,
              ),
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close, size: 20),
            color: AppColors.onSurfaceVariant,
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
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.gray50,
        border: Border(top: BorderSide(color: AppColors.outline, width: 0.5)),
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
                  color: AppColors.gray200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: isImage
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(file, fit: BoxFit.cover),
                      )
                    : const Icon(
                        Icons.insert_drive_file,
                        color: AppColors.onSurfaceVariant,
                      ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => onRemove(index),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: Colors.white,
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
