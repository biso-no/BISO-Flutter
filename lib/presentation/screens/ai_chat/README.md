# BISO AI Chat Module

A premium Flutter implementation for streaming AI chat with SharePoint integration, featuring glassmorphism UI design and real-time tool execution.

## Overview

This module provides a complete AI chat experience that integrates with your existing Appwrite authentication system and streams responses from a Vercel AI SDK v5 backend. The UI features premium glassmorphism design with smooth animations and tool-aware rendering.

## Features

### ✨ Premium UI/UX
- **Glassmorphism Design**: Semi-transparent, blurred elements with elegant depth
- **Smooth Animations**: Spring animations, fade transitions, and micro-interactions
- **Responsive Layout**: Edge-to-edge design with proper safe area handling
- **Dark/Light Theme**: Dynamic theming with brand color integration
- **Custom Components**: No Material Design widgets - fully custom implementation

### 🔄 Streaming Architecture
- **Real-time Streaming**: NDJSON streaming with incremental text rendering
- **Tool Execution**: Live tool state transitions (input → available → output)
- **Error Handling**: Comprehensive error states with retry mechanisms
- **Authentication**: Bearer token authentication with Appwrite integration

### 🛠️ Tool Support
- **SharePoint Search**: Document search with preview and download links
- **Document Statistics**: Analytics cards with document/chunk counts
- **SharePoint Sites**: Site listing with direct navigation
- **Weather**: Clean weather display
- **Dynamic Tools**: Expandable JSON viewer for unknown tools

### 📱 Mobile Optimized
- **Touch Interactions**: Tap effects, long-press actions, and gesture support
- **Keyboard Handling**: Smart input field with multi-line support
- **Accessibility**: Screen reader support and proper focus management
- **Performance**: Optimized rendering with minimal rebuilds

## Architecture

### Core Components

```
lib/presentation/screens/ai_chat/
├── ai_chat_screen.dart           # Main chat screen with streaming logic
└── README.md                     # This documentation

lib/presentation/widgets/ai_chat/
├── ai_message_bubble.dart        # AI response bubbles with glassmorphism
├── user_message_bubble.dart      # User message bubbles with gradients
├── chat_input_field.dart         # Floating input with animations
├── typing_indicator.dart         # Animated typing indicator
└── markdown_text.dart            # Markdown parser for AI responses

lib/data/
├── models/ai_chat_models.dart    # Complete type system for Vercel AI SDK
└── services/ai_chat_service.dart # HTTP streaming client with auth
```

### Data Models

The module uses a comprehensive type system that maps to Vercel AI SDK v5 responses:

```dart
// Core message structure
ChatMessage {
  String? id;
  String role;           // 'user' | 'assistant' | 'system'
  List<MessagePart> parts;
  DateTime? timestamp;
}

// Sealed part types
sealed class MessagePart
├── TextPart(text)
├── ToolPart(toolCallId, toolName, args, result, state)
├── StepStartPart(stepId, title)
└── UnknownPart(type, data)

// Tool execution states
enum ToolPartState {
  inputStreaming,
  inputAvailable,
  outputAvailable,
  outputError
}
```

### Streaming Events

The service emits typed events for real-time UI updates:

```dart
sealed class ConversationEvent
├── MessagePartReceived(messageId, part)
├── TextDeltaReceived(messageId, delta)
├── ToolCallUpdated(messageId, toolPart)
├── StreamCompleted(messageId)
└── StreamError(error, messageId?)
```

## API Integration

### Server Requirements

Your streaming chat API must support:

```http
POST /api/chat
Content-Type: application/json
Authorization: Bearer <APPWRITE_SESSION_TOKEN>

{
  "messages": [
    {
      "role": "user",
      "parts": [
        { "type": "text", "text": "Find latest bylaws section 6.3" }
      ]
    }
  ]
}
```

### Response Format

The server streams NDJSON frames:

```json
{"type": "text-delta", "messageId": "msg_123", "textDelta": "Here are the"}
{"type": "tool-call", "messageId": "msg_123", "toolCallId": "call_456", "toolName": "searchSharePoint", "args": {"query": "bylaws section 6.3"}}
{"type": "tool-result", "messageId": "msg_123", "toolCallId": "call_456", "result": {"results": [...], "message": "Found 5 results"}}
{"type": "finish", "messageId": "msg_123"}
```

### Authentication Flow

1. **Flutter Client**: Gets Appwrite session token
2. **HTTP Request**: Sends `Authorization: Bearer <token>`
3. **Server Validation**: Uses node-appwrite to validate token
4. **Stream Response**: Returns authenticated response

```dart
// Authentication in AiChatService
Future<String?> _getAuthToken() async {
  final user = await _authService.getCurrentUser();
  if (user == null) return null;
  
  final session = await account.getSession(sessionId: 'current');
  return session.secret; // Used as Bearer token
}
```

## Usage

### Basic Integration

1. **Add to Router** (already configured):
```dart
GoRoute(
  path: '/ai-chat',
  name: 'ai-chat',
  builder: (context, state) => const AiChatScreen(),
)
```

2. **Navigate to Chat**:
```dart
context.pushNamed('ai-chat');
```

### Advanced Usage

**Theming Integration**:
```dart
// The chat automatically uses your app's theme
// Colors from AppColors are used throughout
// Dark/light mode switching is automatic
```

## Configuration

### Environment Setup

Update your API constants:

```dart
// lib/core/constants/app_constants.dart
static const String aiApiUrl = 'https://ai.biso.no';
static const String aiChatEndpoint = '/api/chat';
```

### Server CORS Configuration

Ensure your server supports:

```javascript
// Server-side CORS headers
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: POST, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
```

### Tool Configuration

The module supports these built-in tools:

- `searchSharePoint`: Document search with results display
- `getDocumentStats`: Statistics with big-number cards  
- `listSharePointSites`: Site listing with navigation
- `weather`: Clean weather widget
- `dynamic-tool`: Expandable JSON for unknown tools

## Customization

### Styling

The module uses your app's existing design system:

```dart
// Colors from core/constants/app_colors.dart
AppColors.crystalBlue    // Primary brand color
AppColors.emeraldGreen   // Secondary accent
AppColors.sunGold        // Attention/warning
AppColors.skyBlue        // Light accent

// Typography from your app's theme
theme.textTheme.headlineSmall  // Tool headers
theme.textTheme.bodyLarge      // Message text
theme.textTheme.bodySmall      // Timestamps
```

### Animations

Customize timing and easing:

```dart
// In message bubbles
AnimationController(
  duration: const Duration(milliseconds: 500),
  curve: Curves.elasticOut,
)
```

## Performance

### Optimizations

- **Lazy Loading**: Tool outputs render only when needed
- **Animation Cleanup**: All controllers properly disposed
- **Memory Management**: HTTP client reuse and cleanup
- **Incremental Updates**: Only changed parts re-render

### Resource Usage

- **Network**: Streaming reduces total payload size
- **Memory**: Efficient message storage with part deduplication
- **CPU**: Optimized animations with vsync
- **Battery**: Minimal background processing

## Testing

### Manual Testing

1. **Authentication**: Verify login state affects chat access
2. **Streaming**: Test text appears incrementally  
3. **Tools**: Verify tool outputs render correctly
4. **Error Handling**: Test network errors and retries
5. **Theming**: Switch between light/dark modes

### Sample Requests

Test with these example queries:

```dart
// Norwegian query
"Finn siste vedtekter paragraf 6.3"

// English query  
"Show me document statistics"

// Weather query
"What's the weather in Oslo?"

// Site listing
"List all SharePoint sites"
```

## Troubleshooting

### Common Issues

**Authentication Errors**:
```dart
// Check if user is logged in
final isAuth = await _chatService.isAuthenticated();
if (!isAuth) {
  // Redirect to login
}
```

**Streaming Issues**:
```dart
// Verify server CORS and endpoint
const String _baseUrl = 'https://ai.biso.no';
const String _chatEndpoint = '/api/chat';
```

**Tool Rendering**:
```dart
// Check tool result structure
print('Tool result: ${toolPart.result}');
```

### Debug Mode

Enable detailed logging:

```dart
// In ai_chat_service.dart
print('🔥 DEBUG: Tool result - ${toolPart.toJson()}');
print('🔥 DEBUG: Stream chunk - $chunk');
```

## Security

### Best Practices

- **Token Validation**: Server validates all Bearer tokens
- **Input Sanitization**: All user input is sanitized
- **HTTPS Only**: All API calls use secure connections
- **Session Management**: Tokens expire with Appwrite sessions

### Privacy

- **Local Storage**: No chat history stored locally
- **Network**: All communication encrypted in transit
- **Authentication**: Session-based, no permanent tokens

## Contributing

### Adding Tools

1. **Define Model**: Add to `ai_chat_models.dart`
2. **Add Parser**: Update `parseToolResult()` in service
3. **Create Widget**: Add rendering for the new tool output
4. **Update Icons**: Add icon mapping in `_buildToolIcon()`

### Styling Changes

1. **Colors**: Update `app_colors.dart`
2. **Typography**: Modify your app's theme
3. **Animations**: Adjust timing in widget files
4. **Layout**: Update component padding/margins

### Testing

1. **Unit Tests**: Test service methods
2. **Widget Tests**: Test UI components
3. **Integration**: Test full chat flow
4. **Manual**: Verify on different devices

---

This module provides a production-ready AI chat experience with premium design and robust architecture. The glassmorphism UI and smooth animations create a modern, engaging user experience while the tool-aware rendering makes AI responses actionable and informative.