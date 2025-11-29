import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/ai_chat_models.dart';
import '../../../data/services/ai_chat_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/ai_chat/ai_message_bubble.dart';
import '../../widgets/ai_chat/user_message_bubble.dart';
import '../../widgets/ai_chat/chat_input_field.dart';
import '../../widgets/ai_chat/typing_indicator.dart';

import '../../../core/logging/print_migration.dart';

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen>
    with TickerProviderStateMixin {
  final AiChatService _chatService = AiChatService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  bool _isStreaming = false;
  String? _currentStreamingMessageId;
  String? _errorMessage;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _checkAuthAndShowWelcome();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.elasticOut),
        );

    _fadeController.forward();
    _slideController.forward();
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

  Color _getStatusColor() {
    if (_isStreaming) {
      final runningTools = _getRunningTools();
      if (runningTools.isNotEmpty) {
        return AppColors.emeraldGreen;
      }
      return AppColors.crystalBlue;
    }

    if (_errorMessage != null) {
      return AppColors.error;
    }

    return AppColors.crystalBlue;
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
    _fadeController.dispose();
    _slideController.dispose();
    _chatService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(theme, isDark),
      body: Stack(
        children: [
          _buildBackground(isDark),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SizedBox(
                      height: constraints.maxHeight,
                      child: Column(
                        children: [
                          Expanded(child: _buildMessagesList()),
                          if (_errorMessage != null) _buildErrorBar(),
                          _buildChatInput(theme, isDark),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme, bool isDark) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: NavigationUtils.buildBackButton(context, fallbackRoute: '/home'),
      flexibleSpace: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: (isDark ? AppColors.backgroundDark : AppColors.white)
                  .withValues(alpha: 0.8),
              border: Border(
                bottom: BorderSide(
                  color: (isDark ? AppColors.outlineDark : AppColors.outline)
                      .withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [
                  AppColors.crystalBlue.withValues(alpha: 0.2),
                  AppColors.emeraldGreen.withValues(alpha: 0.2),
                ],
              ),
            ),
            child: Icon(
              Icons.psychology_rounded,
              color: AppColors.crystalBlue,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BISO AI Assistant',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                _getStatusText(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _getStatusColor(),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: _clearChat,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Clear chat',
          style: IconButton.styleFrom(
            backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBackground(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  AppColors.backgroundDark,
                  AppColors.charcoalBlack.withValues(alpha: 0.9),
                  AppColors.richNavy.withValues(alpha: 0.8),
                ]
              : [
                  AppColors.background,
                  AppColors.skyBlue.withValues(alpha: 0.1),
                  AppColors.subtleBlue.withValues(alpha: 0.3),
                ],
        ),
      ),
    );
  }

  Widget _buildMessagesList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: _messages.length + (_isStreaming ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _messages.length) {
          // Show typing indicator while streaming
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: TypingIndicator(),
          );
        }

        final message = _messages[index];
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

  Widget _buildErrorBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.error.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: AppColors.error, fontSize: 14),
            ),
          ),
          TextButton(onPressed: _retryLastMessage, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildChatInput(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(
          top: BorderSide(
            color: (isDark ? AppColors.outlineDark : AppColors.outline)
                .withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: (isDark ? AppColors.surfaceDark : AppColors.white)
                  .withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: (isDark ? AppColors.outlineDark : AppColors.outline)
                    .withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: ChatInputField(
              controller: _textController,
              onSend: _sendMessage,
              enabled: !_isStreaming,
              isDark: isDark,
            ),
          ),
        ),
      ),
    );
  }
}
