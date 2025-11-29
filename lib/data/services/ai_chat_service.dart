import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import '../models/ai_chat_models.dart';
import '../../core/logging/app_logger.dart';
import '../../core/constants/app_constants.dart';

import '../../core/logging/print_migration.dart';

class AiChatService {
  // Public assistant API endpoint
  static const String _baseUrl = AppConstants.apiBaseUrl;
  static const String _chatEndpoint = AppConstants.publicAssistantEndpoint;

  final http.Client _httpClient = http.Client();

  /// Get the current Appwrite session token for Bearer authentication
  /// Note: Public assistant doesn't require auth, so this returns null
  /// to avoid CORS issues with Appwrite JWT creation
  Future<String?> _getAuthToken() async {
    // Public assistant API doesn't require authentication
    // Skip JWT creation to avoid CORS issues
    return null;
  }

  /// Stream chat messages to the AI API
  Stream<ConversationEvent> streamChat({
    required List<ChatMessage> messages,
  }) async* {
    try {
      final authToken = await _getAuthToken();

      final request = ChatRequest(messages: messages);
      final uri = Uri.parse('$_baseUrl$_chatEndpoint');

      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'text/plain', // For NDJSON streaming
      };

      // Add auth headers if we have a token
      if (authToken != null) {
        headers['x-appwrite-user-jwt'] = authToken;
        headers['Authorization'] = 'Bearer $authToken';
      }

      final httpRequest = http.Request('POST', uri)
        ..headers.addAll(headers)
        ..body = jsonEncode(request.toJson());

      final streamedResponse = await _httpClient.send(httpRequest);

      if (streamedResponse.statusCode != 200) {
        // Try to read error response
        final errorBody = await streamedResponse.stream.bytesToString();
        String errorMessage;
        try {
          final errorJson = jsonDecode(errorBody);
          errorMessage = errorJson['error'] ?? 'Unknown error';
        } catch (e) {
          errorMessage = 'HTTP ${streamedResponse.statusCode}: $errorBody';
        }
        yield StreamError(error: errorMessage);
        return;
      }

      // Track the current assistant message for streaming text
      // String? currentAssistantMessageId;
      final Map<String, String> accumulatedText = {};
      final Map<String, ToolPart> toolCalls = {};

      await for (final chunk
          in streamedResponse.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (chunk.trim().isEmpty) continue;

        try {
          // Handle Server-Sent Events format
          String jsonString = chunk;

          // Remove SSE 'data: ' prefix if present
          if (chunk.startsWith('data: ')) {
            jsonString = chunk.substring(6); // Remove 'data: '
          }

          // Skip SSE control messages
          if (jsonString == '[DONE]') {
            break;
          }

          // Skip empty data chunks
          if (jsonString.trim().isEmpty) continue;

          final frameData = jsonDecode(jsonString);

          // Handle different frame types from Vercel AI SDK
          final frameType = frameData['type'] as String?;
          final messageId =
              frameData['id']
                  as String?; // Vercel AI uses 'id' instead of 'messageId'

          switch (frameType) {
            case 'start':
              // Stream started - no action needed
              break;

            case 'start-step':
              // Step started - no action needed
              break;

            case 'text-start':
              // Text generation started for message
              if (messageId != null) {
                accumulatedText[messageId] = '';
              }
              break;

            case 'text-delta':
              final textDelta = frameData['delta'] as String?;

              if (messageId != null && textDelta != null) {
                accumulatedText[messageId] =
                    (accumulatedText[messageId] ?? '') + textDelta;

                yield TextDeltaReceived(messageId: messageId, delta: textDelta);
              }
              break;

            case 'text-end':
              // Text generation completed - no specific action needed
              break;

            case 'tool-call':
            case 'tool-input-start':
              final toolCallId = frameData['toolCallId'] as String?;
              final toolName = frameData['toolName'] as String?;
              final args = frameData['args'] as Map<String, dynamic>?;

              if (messageId != null && toolCallId != null && toolName != null) {
                final toolPart = ToolPart(
                  toolCallId: toolCallId,
                  toolName: toolName,
                  args: args,
                  state: ToolPartState.inputStreaming,
                );

                toolCalls[toolCallId] = toolPart;

                yield ToolCallUpdated(messageId: messageId, toolPart: toolPart);
              }
              break;

            case 'tool-call-delta':
            case 'tool-input-delta':
              final toolCallId = frameData['toolCallId'] as String?;

              if (toolCallId != null && toolCalls.containsKey(toolCallId)) {
                // Update tool args with delta (for streaming args)
                final currentTool = toolCalls[toolCallId]!;
                toolCalls[toolCallId] = currentTool.copyWith(
                  state: ToolPartState.inputStreaming,
                );
              }
              break;

            case 'tool-input-available':
              final toolCallId = frameData['toolCallId'] as String?;

              if (toolCallId != null && toolCalls.containsKey(toolCallId)) {
                final currentTool = toolCalls[toolCallId]!;
                toolCalls[toolCallId] = currentTool.copyWith(
                  state: ToolPartState.inputAvailable,
                );

                if (messageId != null) {
                  yield ToolCallUpdated(
                    messageId: messageId,
                    toolPart: toolCalls[toolCallId]!,
                  );
                }
              }
              break;

            case 'tool-result':
            case 'tool-output-available':
              final toolCallId = frameData['toolCallId'] as String?;
              final result = frameData['result'] as Map<String, dynamic>?;
              final isError = frameData['isError'] as bool? ?? false;

              if (messageId != null &&
                  toolCallId != null &&
                  toolCalls.containsKey(toolCallId)) {
                final updatedTool = toolCalls[toolCallId]!.copyWith(
                  result: result,
                  state: isError
                      ? ToolPartState.outputError
                      : ToolPartState.outputAvailable,
                  isError: isError,
                );

                toolCalls[toolCallId] = updatedTool;

                yield ToolCallUpdated(
                  messageId: messageId,
                  toolPart: updatedTool,
                );
              }
              break;

            case 'finish-step':
              // Step completed - no action needed
              break;

            case 'finish':
              // Stream completed
              if (messageId != null) {
                yield StreamCompleted(messageId: messageId);
              } else {
                // If no messageId, use the last accumulated message
                final lastMessageId = accumulatedText.keys.isNotEmpty
                    ? accumulatedText.keys.last
                    : DateTime.now().millisecondsSinceEpoch.toString();
                yield StreamCompleted(messageId: lastMessageId);
              }
              break;

            case 'error':
              final error =
                  frameData['error'] as String? ?? 'Unknown streaming error';
              yield StreamError(error: error, messageId: messageId);
              break;

            default:
              // Handle unknown frame types gracefully
              AppLogger.warning(
                'Unknown frame type in AI chat stream',
                extra: {'frame_type': frameType, 'service': 'ai_chat'},
              );
              break;
          }
        } catch (e) {
          AppLogger.error(
            'Error parsing AI chat stream chunk',
            error: e,
            extra: {'chunk': chunk, 'service': 'ai_chat'},
          );
          // Continue processing other chunks
        }
      }
    } on SocketException catch (e) {
      yield StreamError(error: 'Network error: ${e.message}');
    } on FormatException catch (e) {
      yield StreamError(error: 'Invalid response format: ${e.message}');
    } on TimeoutException catch (e) {
      yield StreamError(error: 'Request timeout: ${e.message}');
    } catch (e) {
      yield StreamError(error: 'Unexpected error: $e');
    }
  }

  /// Create a new user message
  ChatMessage createUserMessage(String text) {
    return ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'user',
      parts: [TextPart(text: text)],
      timestamp: DateTime.now(),
    );
  }

  /// Create an assistant message with streaming support
  ChatMessage createAssistantMessage({String? id}) {
    return ChatMessage(
      id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'assistant',
      parts: [],
      timestamp: DateTime.now(),
    );
  }

  /// Update a message with a new text part or append to existing text
  ChatMessage updateMessageWithText(ChatMessage message, String textDelta) {
    final existingTextParts = message.parts.whereType<TextPart>().toList();
    final otherParts = message.parts
        .where((part) => part is! TextPart)
        .toList();

    if (existingTextParts.isEmpty) {
      // Create new text part
      return message.copyWith(
        parts: [
          ...otherParts,
          TextPart(text: textDelta),
        ],
      );
    } else {
      // Append to last text part
      final lastTextPart = existingTextParts.last;
      final updatedTextPart = lastTextPart.copyWith(
        text: lastTextPart.text + textDelta,
      );

      // Replace the last text part
      final allParts = message.parts.toList();
      final lastTextIndex = allParts.lastIndexWhere((part) => part is TextPart);
      allParts[lastTextIndex] = updatedTextPart;

      return message.copyWith(parts: allParts);
    }
  }

  /// Update a message with a tool part
  ChatMessage updateMessageWithTool(ChatMessage message, ToolPart toolPart) {
    final parts = message.parts.toList();

    // Find existing tool part with same toolCallId
    final existingIndex = parts.indexWhere(
      (part) => part is ToolPart && part.toolCallId == toolPart.toolCallId,
    );

    if (existingIndex >= 0) {
      // Replace existing tool part
      parts[existingIndex] = toolPart;
    } else {
      // Add new tool part
      parts.add(toolPart);
    }

    return message.copyWith(parts: parts);
  }

  /// Parse tool result based on tool name
  dynamic parseToolResult(String toolName, Map<String, dynamic> result) {
    switch (toolName) {
      case 'searchSharePoint':
        return SharePointSearchResponse.fromJson(result);
      case 'searchSiteContent':
        return SiteContentSearchResponse.fromJson(result);
      case 'getDocumentStats':
        return DocumentStatsResponse.fromJson(result);
      case 'listSharePointSites':
        return SharePointSitesResponse.fromJson(result);
      case 'weather':
        return WeatherResponse.fromJson(result);
      default:
        return result; // Return raw result for unknown tools
    }
  }

  /// Check if user is authenticated for AI chat
  /// Note: Public assistant doesn't require auth, but we still check
  /// to optionally include user context in requests
  Future<bool> isAuthenticated() async {
    // Public assistant is available to all users
    // Auth token is optional - used for personalization if available
    return true;
  }

  /// Main streaming method that delegates to the preferred implementation
  /// Set useSSE = true to use the flutter_client_sse implementation
  Stream<ConversationEvent> streamChatMessages({
    required List<ChatMessage> messages,
    bool useSSE = true,
  }) {
    if (useSSE) {
      return streamChatWithSSE(messages: messages);
    } else {
      return streamChat(messages: messages);
    }
  }

  /// Stream chat messages using flutter_client_sse (Clean SSE implementation)
  Stream<ConversationEvent> streamChatWithSSE({
    required List<ChatMessage> messages,
  }) async* {
    late StreamController<ConversationEvent> controller;
    controller = StreamController<ConversationEvent>();

    try {
      final authToken = await _getAuthToken();
      final request = ChatRequest(messages: messages);
      final uri = Uri.parse('$_baseUrl$_chatEndpoint');

      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
      };

      if (authToken != null) {
        headers['X-Appwrite-JWT'] = authToken;
        headers['Authorization'] = 'Bearer $authToken';
      }

      // Track accumulated data for streaming
      final Map<String, String> accumulatedText = {};
      final Map<String, ToolPart> toolCalls = {};
      String? currentStreamingMessageId;

      // Create a fallback message ID for tool-only responses
      final fallbackMessageId = DateTime.now().millisecondsSinceEpoch
          .toString();

      logPrint('🌐 [SSE] Connecting to: ${uri.toString()}');
      logPrint('📋 [SSE] Headers: $headers');
      logPrint('📦 [SSE] Body: ${jsonEncode(request.toJson())}');

      // SSE connection is working - skip HTTP test for performance

      // Setup flutter_client_sse connection
      SSEClient.subscribeToSSE(
        method: SSERequestType.POST,
        url: uri.toString(),
        header: headers,
        body: request.toJson(),
      ).listen(
        (event) {
          final eventData = event.data ?? '';
          logPrint(
            '📡 [SSE] Event received - ID: ${event.id}, Event: ${event.event}, Data: "$eventData"',
          );

          // Check if we're getting HTML error pages
          if (eventData.startsWith('<!DOCTYPE html') ||
              eventData.startsWith('<html')) {
            logPrint('❌ [SSE] Received HTML error page instead of JSON stream');
            logPrint(
              '❌ [SSE] This indicates a server-side authentication or routing issue',
            );
            if (!controller.isClosed) {
              controller.add(
                StreamError(
                  error:
                      'Server returned HTML error page. Check authentication and server logs.',
                ),
              );
              controller.close();
            }
            return;
          }

          if (eventData.trim().isEmpty || eventData == '[DONE]') {
            logPrint('🏁 [SSE] Stream ended');
            if (!controller.isClosed) {
              final messageId =
                  currentStreamingMessageId ??
                  accumulatedText.keys.lastOrNull ??
                  DateTime.now().millisecondsSinceEpoch.toString();
              controller.add(StreamCompleted(messageId: messageId));
              controller.close();
            }
            return;
          }

          try {
            final frameData = jsonDecode(eventData);
            final conversationEvent = _handleSSEData(
              frameData,
              accumulatedText,
              toolCalls,
              currentStreamingMessageId,
              fallbackMessageId,
            );

            // Update current streaming message ID if we get one from server
            if (conversationEvent is TextDeltaReceived &&
                currentStreamingMessageId == null) {
              currentStreamingMessageId = conversationEvent.messageId;
              logPrint(
                '🆔 [SSE] Set streaming message ID from text delta: $currentStreamingMessageId',
              );
            }

            // Also capture message ID from tool events to ensure tools can attach
            if (conversationEvent is ToolCallUpdated &&
                currentStreamingMessageId == null) {
              currentStreamingMessageId = conversationEvent.messageId;
              logPrint(
                '🆔 [SSE] Set streaming message ID from tool event: $currentStreamingMessageId',
              );
            }

            if (conversationEvent != null && !controller.isClosed) {
              logPrint(
                '✅ [SSE] Adding event: ${conversationEvent.runtimeType}',
              );
              controller.add(conversationEvent);
            }
          } catch (e) {
            logPrint('❌ [SSE] Parse error: $e');
            logPrint('📄 [SSE] Raw data: "$eventData"');
          }
        },
        onError: (error) {
          logPrint('💥 [SSE] Connection error: $error');
          if (!controller.isClosed) {
            controller.add(StreamError(error: 'SSE connection failed: $error'));
            controller.close();
          }
        },
        onDone: () {
          logPrint('🏁 [SSE] Connection closed');
          if (!controller.isClosed) {
            final messageId =
                currentStreamingMessageId ??
                accumulatedText.keys.lastOrNull ??
                DateTime.now().millisecondsSinceEpoch.toString();
            controller.add(StreamCompleted(messageId: messageId));
            controller.close();
          }
        },
      );

      // Yield events from the controller stream
      await for (final event in controller.stream) {
        yield event;
      }
    } on SocketException catch (e) {
      yield StreamError(error: 'Network error: ${e.message}');
    } catch (e) {
      yield StreamError(error: 'Unexpected error: $e');
    } finally {
      if (!controller.isClosed) {
        controller.close();
      }
    }
  }

  /// Handle SSE data stream (clean parsing for flutter_client_sse)
  ConversationEvent? _handleSSEData(
    Map<String, dynamic> frameData,
    Map<String, String> accumulatedText,
    Map<String, ToolPart> toolCalls,
    String? currentStreamingMessageId,
    String fallbackMessageId,
  ) {
    try {
      final frameType = frameData['type'] as String?;
      final messageId = frameData['id'] as String?;

      logPrint('📝 [SSE] Processing: $frameType, messageId: $messageId');

      switch (frameType) {
        case 'start':
        case 'start-step':
        case 'finish-step':
          return null;

        case 'text-start':
          if (messageId != null) {
            accumulatedText[messageId] = '';
            logPrint('📝 [SSE] Text started for: $messageId');
          }
          return null;

        case 'text-delta':
          final textDelta = frameData['delta'] as String?;
          if (messageId != null && textDelta != null) {
            accumulatedText[messageId] =
                (accumulatedText[messageId] ?? '') + textDelta;
            logPrint(
              '📝 [SSE] Text delta: "$textDelta" (accumulated: ${accumulatedText[messageId]?.length ?? 0} chars)',
            );
            return TextDeltaReceived(messageId: messageId, delta: textDelta);
          }
          return null;

        case 'text-end':
          logPrint('📝 [SSE] Text generation completed for: $messageId');
          return null;

        case 'tool-input-start':
        case 'tool-call':
          final toolCallId = frameData['toolCallId'] as String?;
          final toolName = frameData['toolName'] as String?;
          final args = frameData['args'] as Map<String, dynamic>?;

          if (toolCallId != null && toolName != null) {
            // Use message ID from event, or current streaming ID, or fallback
            final targetMessageId =
                messageId ?? currentStreamingMessageId ?? fallbackMessageId;

            logPrint(
              '🔧 [SSE] Tool started: $toolName ($toolCallId) for message: $targetMessageId',
            );
            logPrint(
              '🔧 [SSE] messageId=$messageId, currentStreaming=$currentStreamingMessageId, fallback=$fallbackMessageId',
            );

            final toolPart = ToolPart(
              toolCallId: toolCallId,
              toolName: toolName,
              args: args,
              state: ToolPartState.inputStreaming,
            );

            toolCalls[toolCallId] = toolPart;

            // Set currentStreamingMessageId if we don't have one yet
            if (currentStreamingMessageId == null) {
              currentStreamingMessageId = targetMessageId;
              logPrint(
                '🆔 [SSE] Set current streaming ID from tool start: $currentStreamingMessageId',
              );
            }

            return ToolCallUpdated(
              messageId: targetMessageId,
              toolPart: toolPart,
            );
          }
          return null;

        case 'tool-input-delta':
          final toolCallId = frameData['toolCallId'] as String?;
          final inputTextDelta = frameData['inputTextDelta'] as String?;

          if (toolCallId != null && toolCalls.containsKey(toolCallId)) {
            final targetMessageId =
                messageId ?? currentStreamingMessageId ?? fallbackMessageId;
            logPrint(
              '🔧 [SSE] Tool input delta: $toolCallId for message: $targetMessageId, delta: $inputTextDelta',
            );

            final currentTool = toolCalls[toolCallId]!;
            toolCalls[toolCallId] = currentTool.copyWith(
              state: ToolPartState.inputStreaming,
            );

            return ToolCallUpdated(
              messageId: targetMessageId,
              toolPart: toolCalls[toolCallId]!,
            );
          }
          return null;

        case 'tool-input-available':
          final toolCallId = frameData['toolCallId'] as String?;

          if (toolCallId != null && toolCalls.containsKey(toolCallId)) {
            final targetMessageId =
                messageId ?? currentStreamingMessageId ?? fallbackMessageId;
            logPrint(
              '🔧 [SSE] Tool input available: $toolCallId for message: $targetMessageId',
            );

            final currentTool = toolCalls[toolCallId]!;
            toolCalls[toolCallId] = currentTool.copyWith(
              state: ToolPartState.inputAvailable,
            );

            return ToolCallUpdated(
              messageId: targetMessageId,
              toolPart: toolCalls[toolCallId]!,
            );
          }
          return null;

        case 'tool-output-available':
        case 'tool-result':
          final toolCallId = frameData['toolCallId'] as String?;
          final result =
              frameData['output'] as Map<String, dynamic>? ??
              frameData['result'] as Map<String, dynamic>?;
          final isError = frameData['isError'] as bool? ?? false;

          if (toolCallId != null && toolCalls.containsKey(toolCallId)) {
            final targetMessageId =
                messageId ?? currentStreamingMessageId ?? fallbackMessageId;
            logPrint(
              '🔧 [SSE] Tool result: $toolCallId for message: $targetMessageId',
            );
            logPrint(
              '📋 [SSE] Tool result data: ${result != null ? jsonEncode(result) : 'null'}',
            );

            // Log specific fields for SharePoint results
            if (toolCalls[toolCallId]?.toolName == 'searchSharePoint' &&
                result != null) {
              final results = result['results'] as List<dynamic>? ?? [];
              logPrint('📄 [SSE] SharePoint results count: ${results.length}');
              for (int i = 0; i < results.length && i < 3; i++) {
                final item = results[i] as Map<String, dynamic>?;
                if (item != null) {
                  logPrint(
                    '📄 [SSE] Result $i: title="${item['title']}", url="${item['documentViewerUrl']}"',
                  );
                }
              }
            }

            final updatedTool = toolCalls[toolCallId]!.copyWith(
              result: result,
              state: isError
                  ? ToolPartState.outputError
                  : ToolPartState.outputAvailable,
              isError: isError,
            );

            toolCalls[toolCallId] = updatedTool;

            return ToolCallUpdated(
              messageId: targetMessageId,
              toolPart: updatedTool,
            );
          }
          return null;

        case 'finish':
          final targetMessageId =
              messageId ??
              currentStreamingMessageId ??
              accumulatedText.keys.lastOrNull ??
              DateTime.now().millisecondsSinceEpoch.toString();
          logPrint('✅ [SSE] Stream finished for: $targetMessageId');
          return StreamCompleted(messageId: targetMessageId);

        case 'error':
          final error =
              frameData['error'] as String? ?? 'Unknown streaming error';
          final targetMessageId = messageId ?? currentStreamingMessageId;
          logPrint('❌ [SSE] Stream error: $error');
          return StreamError(error: error, messageId: targetMessageId);

        default:
          logPrint('⚠️ [SSE] Unknown frame type: $frameType');
          return null;
      }
    } catch (e) {
      logPrint('💥 [SSE] Parse error: $e');
      return StreamError(error: 'Parse error: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _httpClient.close();
  }
}
