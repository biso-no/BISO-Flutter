import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/biso_chrome.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/ai_chat_models.dart';
import '../../../data/services/ai_chat_service.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../widgets/ai_chat/ai_message_bubble.dart';
import '../../widgets/ai_chat/chat_input_field.dart';
import '../../widgets/ai_chat/typing_indicator.dart';
import '../../widgets/ai_chat/user_message_bubble.dart';
import '../../widgets/biso/biso.dart';

import '../../../core/logging/print_migration.dart';

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key, this.chatService});

  /// Overridable so tests can supply a fake instead of the real
  /// network-backed service; production always leaves this null and gets a
  /// real [AiChatService].
  final AiChatService? chatService;

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  late final AiChatService _chatService = widget.chatService ?? AiChatService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  bool _isStreaming = false;
  String? _currentStreamingMessageId;
  String? _errorMessage;
  double _lastBottomInset = 0;

  @override
  void initState() {
    super.initState();
    _checkAuthAndShowWelcome();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The message list doesn't reverse-anchor to the bottom the way
    // `chat_conversation_screen.dart`'s does, so opening the keyboard
    // shrinks the scroll viewport without moving the scroll position: the
    // newest message can end up hidden below the now-higher composer.
    // Re-run the same scroll-to-bottom used after every send whenever the
    // keyboard inset grows.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    if (bottomInset > _lastBottomInset) {
      _scrollToBottom();
    }
    _lastBottomInset = bottomInset;
  }

  Future<void> _checkAuthAndShowWelcome() async {
    final isAuth = await _chatService.isAuthenticated();
    if (!isAuth) {
      setState(() {
        _errorMessage = 'Please log in to use the AI assistant';
      });
      return;
    }

    // Add welcome message
    final welcomeMessage = ChatMessage(
      id: 'welcome',
      role: 'assistant',
      parts: [
        const TextPart(
          text:
              '👋 Hei! Jeg er din AI-assistent for BISO. Jeg kan hjelpe deg med å finne informasjon om vedtekter, retningslinjer og andre dokumenter. Spør meg om hva som helst!\n\nHello! I\'m your AI assistant for BISO. I can help you find information about bylaws, guidelines, and other documents. Ask me anything!',
        ),
      ],
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(welcomeMessage);
    });
  }

  void _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isStreaming) return;

    final userMessage = _chatService.createUserMessage(text);
    _textController.clear();

    setState(() {
      _messages.add(userMessage);
      _isStreaming = true;
      _errorMessage = null;
    });

    _scrollToBottom();

    try {
      logPrint('🚀 [AI_CHAT] Starting stream for ${_messages.length} messages');

      // Use the new streamChatMessages method with flutter_client_sse
      await for (final event in _chatService.streamChatMessages(
        messages: _messages,
        useSSE: true,
      )) {
        logPrint('📥 [AI_CHAT] Received event: ${event.runtimeType}');

        switch (event) {
          case MessagePartReceived(:final messageId, :final part):
            logPrint(
              '📝 [AI_CHAT] MessagePart received for $messageId: ${part.runtimeType}',
            );
            // Handle new message part
            break;

          case TextDeltaReceived(:final messageId, :final delta):
            logPrint('✍️ [AI_CHAT] TextDelta for $messageId: "$delta"');
            _ensureAssistantMessage(messageId);
            _updateMessageWithTextDelta(messageId, delta);
            break;

          case ToolCallUpdated(:final messageId, :final toolPart):
            logPrint(
              '🔧 [AI_CHAT] ToolCall updated for $messageId: ${toolPart.toolName} (${toolPart.state})',
            );
            logPrint('🔧 [AI_CHAT] ToolCall args: ${toolPart.args}');
            logPrint(
              '🔧 [AI_CHAT] ToolCall result: ${toolPart.result != null ? 'has result' : 'no result'}',
            );
            _ensureAssistantMessage(messageId);
            _updateMessageWithTool(messageId, toolPart);
            break;

          case StreamCompleted(:final messageId):
            logPrint('✅ [AI_CHAT] Stream completed for $messageId');
            setState(() {
              _isStreaming = false;
              _currentStreamingMessageId = null;
            });
            break;

          case StreamError(:final error):
            logPrint('❌ [AI_CHAT] Stream error: $error');
            setState(() {
              _isStreaming = false;
              _currentStreamingMessageId = null;
              _errorMessage = error;
            });
            break;
        }

        _scrollToBottom();
      }

      logPrint('🏁 [AI_CHAT] Stream finished');
    } catch (e) {
      logPrint('💥 [AI_CHAT] Stream exception: $e');
      setState(() {
        _isStreaming = false;
        _currentStreamingMessageId = null;
        _errorMessage = 'Failed to send message: $e';
      });
    }
  }

  void _ensureAssistantMessage(String messageId) {
    // Only create assistant message if we don't have one yet
    if (_currentStreamingMessageId == null) {
      logPrint('🤖 [AI_CHAT] Creating assistant message with ID: $messageId');
      final assistantMessage = _chatService.createAssistantMessage(
        id: messageId,
      );
      setState(() {
        _messages.add(assistantMessage);
        _currentStreamingMessageId = messageId;
      });
      _scrollToBottom();
    }
  }

  void _updateMessageWithTextDelta(String messageId, String delta) {
    logPrint('🔄 [AI_CHAT] Updating message $messageId with delta: "$delta"');

    setState(() {
      var messageIndex = _messages.indexWhere((msg) => msg.id == messageId);
      logPrint(
        '📍 [AI_CHAT] Message index: $messageIndex (total messages: ${_messages.length})',
      );

      // If message not found by server ID, try to find the current streaming message
      if (messageIndex < 0 && _currentStreamingMessageId != null) {
        messageIndex = _messages.indexWhere(
          (msg) => msg.id == _currentStreamingMessageId,
        );
        if (messageIndex >= 0) {
          logPrint(
            '🔄 [AI_CHAT] Updating current streaming message ID from $_currentStreamingMessageId to $messageId',
          );
          // Update the message ID to match the server's ID
          _messages[messageIndex] = _messages[messageIndex].copyWith(
            id: messageId,
          );
          _currentStreamingMessageId = messageId;
        }
      }

      if (messageIndex >= 0) {
        final oldMessage = _messages[messageIndex];
        logPrint('📝 [AI_CHAT] Old message parts: ${oldMessage.parts.length}');

        _messages[messageIndex] = _chatService.updateMessageWithText(
          _messages[messageIndex],
          delta,
        );

        final newMessage = _messages[messageIndex];
        logPrint('📝 [AI_CHAT] New message parts: ${newMessage.parts.length}');
        logPrint(
          '📄 [AI_CHAT] Current text content: "${newMessage.textContent}"',
        );
      } else {
        logPrint('❌ [AI_CHAT] Message not found for ID: $messageId');
        logPrint(
          '📋 [AI_CHAT] Available message IDs: ${_messages.map((m) => m.id).toList()}',
        );
      }
    });
  }

  void _updateMessageWithTool(String messageId, ToolPart toolPart) {
    logPrint(
      '🔧 [AI_CHAT] Updating message $messageId with tool: ${toolPart.toolName} (${toolPart.state})',
    );

    setState(() {
      var messageIndex = _messages.indexWhere((msg) => msg.id == messageId);
      logPrint('📍 [AI_CHAT] Tool message index: $messageIndex');

      // If message not found by tool message ID, try to find the current streaming message
      if (messageIndex < 0 && _currentStreamingMessageId != null) {
        messageIndex = _messages.indexWhere(
          (msg) => msg.id == _currentStreamingMessageId,
        );
        if (messageIndex >= 0) {
          logPrint(
            '🔄 [AI_CHAT] Updating tool message ID from $_currentStreamingMessageId to $messageId',
          );
          // Update the message ID to match the tool event's ID
          _messages[messageIndex] = _messages[messageIndex].copyWith(
            id: messageId,
          );
          _currentStreamingMessageId = messageId;
        }
      }

      if (messageIndex >= 0) {
        final oldMessage = _messages[messageIndex];
        logPrint('🔧 [AI_CHAT] Old tool parts: ${oldMessage.toolParts.length}');

        _messages[messageIndex] = _chatService.updateMessageWithTool(
          _messages[messageIndex],
          toolPart,
        );

        final newMessage = _messages[messageIndex];
        logPrint('🔧 [AI_CHAT] New tool parts: ${newMessage.toolParts.length}');

        // Add haptic feedback when tool completes
        if (toolPart.state == ToolPartState.outputAvailable) {
          logPrint('✅ [AI_CHAT] Tool completed: ${toolPart.toolName}');
          // Optional: Add haptic feedback
          // HapticFeedback.lightImpact();
        }
      } else {
        logPrint('❌ [AI_CHAT] Tool message not found for ID: $messageId');
        logPrint(
          '📋 [AI_CHAT] Available message IDs: ${_messages.map((m) => m.id).toList()}',
        );
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearChat() {
    setState(() {
      _messages.clear();
      _isStreaming = false;
      _currentStreamingMessageId = null;
      _errorMessage = null;
    });
    _checkAuthAndShowWelcome();
  }

  void _retryLastMessage() {
    if (_messages.isNotEmpty && _messages.last.role == 'user') {
      final lastUserMessage = _messages.last;
      final textContent = lastUserMessage.textContent;

      // Remove any trailing assistant messages that failed
      while (_messages.isNotEmpty && _messages.last.role == 'assistant') {
        _messages.removeLast();
      }

      setState(() {
        _textController.text = textContent;
        _errorMessage = null;
      });
    }
  }

  String _getStatusText() {
    if (_isStreaming) {
      // Check if there are any tools currently executing
      final runningTools = _getRunningTools();
      if (runningTools.isNotEmpty) {
        return 'Using ${runningTools.first}...';
      }
      return 'Thinking...';
    }

    if (_errorMessage != null) {
      return 'Error occurred';
    }

    return 'Ready to help';
  }

  List<String> _getRunningTools() {
    if (_messages.isEmpty) return [];

    final lastMessage = _messages.last;
    if (lastMessage.role != 'assistant') return [];

    return lastMessage.toolParts
        .where(
          (tool) =>
              tool.state == ToolPartState.inputStreaming ||
              tool.state == ToolPartState.inputAvailable,
        )
        .map((tool) => _getToolDisplayName(tool.toolName))
        .toList();
  }

  String _getToolDisplayName(String toolName) {
    switch (toolName) {
      case 'searchSharePoint':
        return 'Document Search';
      case 'searchSiteContent':
        return 'Site Content';
      case 'getDocumentStats':
        return 'Document Stats';
      case 'listSharePointSites':
        return 'Site Listing';
      case 'weather':
        return 'Weather';
      default:
        return toolName;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _chatService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BisoPage(
      title: 'BISO AI Assistant',
      largeTitle: false,
      leading: BisoBackButton(
        onPressed: () =>
            NavigationUtils.safeGoBack(context, fallbackRoute: '/home'),
      ),
      actions: [
        BisoHeaderAction(
          icon: CupertinoIcons.arrow_clockwise,
          tooltip: l10n?.newConversationMessage ?? 'New conversation',
          onPressed: _clearChat,
        ),
      ],
      // `BisoPageInsets.padding` needs a context *below* `BisoPage` in the
      // tree, not the screen's own build context — see the identical note in
      // `chat_conversation_screen.dart`. Without a `Builder`,
      // `BisoPageInsets.maybeOf` returns null here and the list's bottom
      // clearance silently omits the composer's own height.
      body: Builder(builder: _buildMessagesList),
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_errorMessage != null) _buildErrorBar(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: BisoChrome(
              key: const ValueKey('ai-chat-composer-chrome'),
              radius: 26,
              child: ChatInputField(
                controller: _textController,
                onSend: _sendMessage,
                enabled: !_isStreaming,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList(BuildContext context) {
    final itemCount =
        1 + _messages.length + (_isStreaming ? 1 : 0); // +1 for status row

    return ListView.builder(
      controller: _scrollController,
      padding: BisoPageInsets.padding(
        context,
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _StatusRow(text: _getStatusText());
        }

        final messageIndex = index - 1;
        if (messageIndex >= _messages.length) {
          // Show typing indicator while streaming
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: TypingIndicator(),
          );
        }

        final message = _messages[messageIndex];
        final isUser = message.role == 'user';
        final isStreamingThisMessage =
            _isStreaming && message.id == _currentStreamingMessageId;

        logPrint(
          '🎯 [AI_CHAT] Rendering message ${message.id} (${message.role})',
        );
        if (!isUser) {
          logPrint(
            '🔄 [AI_CHAT] AI message - isStreaming: $_isStreaming, currentStreamingId: $_currentStreamingMessageId',
          );
          logPrint(
            '📊 [AI_CHAT] isStreamingThisMessage: $isStreamingThisMessage',
          );
          logPrint(
            '📝 [AI_CHAT] Message text content: "${message.textContent}"',
          );
        }

        return Padding(
          key: ValueKey('ai-chat-message-${message.id}'),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: isUser
              ? UserMessageBubble(message: message)
              : AiMessageBubble(
                  message: message,
                  isStreaming: isStreamingThisMessage,
                ),
        );
      },
    );
  }

  Widget _buildErrorBar(BuildContext context) {
    final palette = BisoPalette.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.exclamationmark_circle,
            color: palette.error,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: palette.error, fontSize: 14),
            ),
          ),
          TextButton(onPressed: _retryLastMessage, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// The header's old changing status line ("Thinking...", "Using X...",
/// "Error occurred", "Ready to help"), moved to the top of the message list
/// so the compact header title can stay a single, static line.
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BisoIconTile(
              icon: CupertinoIcons.sparkles,
              accent: BisoAccent.violet,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: palette.muted),
            ),
          ],
        ),
      ),
    );
  }
}
