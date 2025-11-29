import 'package:equatable/equatable.dart';

/// Base sealed class for message parts
sealed class MessagePart extends Equatable {
  const MessagePart();

  factory MessagePart.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case 'text':
        return TextPart.fromJson(json);
      case 'tool':
        return ToolPart.fromJson(json);
      case 'step-start':
        return StepStartPart.fromJson(json);
      default:
        return UnknownPart.fromJson(json);
    }
  }

  Map<String, dynamic> toJson();
}

/// Text content part
class TextPart extends MessagePart {
  final String text;

  const TextPart({required this.text});

  factory TextPart.fromJson(Map<String, dynamic> json) {
    return TextPart(text: json['text'] as String);
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'text', 'text': text};
  }

  TextPart copyWith({String? text}) {
    return TextPart(text: text ?? this.text);
  }

  @override
  List<Object?> get props => [text];
}

/// Tool call part
class ToolPart extends MessagePart {
  final String toolCallId;
  final String toolName;
  final Map<String, dynamic>? args;
  final Map<String, dynamic>? result;
  final ToolPartState state;
  final bool? isError;

  const ToolPart({
    required this.toolCallId,
    required this.toolName,
    this.args,
    this.result,
    required this.state,
    this.isError,
  });

  factory ToolPart.fromJson(Map<String, dynamic> json) {
    return ToolPart(
      toolCallId: json['toolCallId'] as String,
      toolName: json['toolName'] as String,
      args: json['args'] as Map<String, dynamic>?,
      result: json['result'] as Map<String, dynamic>?,
      state: ToolPartState.fromString(json['state'] as String),
      isError: json['isError'] as bool?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'tool',
      'toolCallId': toolCallId,
      'toolName': toolName,
      'args': args,
      'result': result,
      'state': state.value,
      'isError': isError,
    };
  }

  ToolPart copyWith({
    String? toolCallId,
    String? toolName,
    Map<String, dynamic>? args,
    Map<String, dynamic>? result,
    ToolPartState? state,
    bool? isError,
  }) {
    return ToolPart(
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
      args: args ?? this.args,
      result: result ?? this.result,
      state: state ?? this.state,
      isError: isError ?? this.isError,
    );
  }

  @override
  List<Object?> get props => [
    toolCallId,
    toolName,
    args,
    result,
    state,
    isError,
  ];
}

/// Tool execution states
enum ToolPartState {
  inputStreaming('input-streaming'),
  inputAvailable('input-available'),
  outputAvailable('output-available'),
  outputError('output-error');

  const ToolPartState(this.value);
  final String value;

  static ToolPartState fromString(String value) {
    return values.firstWhere(
      (state) => state.value == value,
      orElse: () => inputStreaming,
    );
  }
}

/// Step start part (for multi-step reasoning)
class StepStartPart extends MessagePart {
  final String stepId;
  final String? title;

  const StepStartPart({required this.stepId, this.title});

  factory StepStartPart.fromJson(Map<String, dynamic> json) {
    return StepStartPart(
      stepId: json['stepId'] as String,
      title: json['title'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'step-start', 'stepId': stepId, 'title': title};
  }

  @override
  List<Object?> get props => [stepId, title];
}

/// Unknown part type (for future extensibility)
class UnknownPart extends MessagePart {
  final String type;
  final Map<String, dynamic> data;

  const UnknownPart({required this.type, required this.data});

  factory UnknownPart.fromJson(Map<String, dynamic> json) {
    return UnknownPart(
      type: json['type'] as String,
      data: Map<String, dynamic>.from(json),
    );
  }

  @override
  Map<String, dynamic> toJson() => data;

  @override
  List<Object?> get props => [type, data];
}

/// Chat message model
class ChatMessage extends Equatable {
  final String? id;
  final String role; // 'user', 'assistant', 'system'
  final List<MessagePart> parts;
  final DateTime? timestamp;

  const ChatMessage({
    this.id,
    required this.role,
    required this.parts,
    this.timestamp,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final partsList = json['parts'] as List<dynamic>? ?? [];
    return ChatMessage(
      id: json['id'] as String?,
      role: json['role'] as String,
      parts: partsList
          .map((part) => MessagePart.fromJson(part as Map<String, dynamic>))
          .toList(),
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'parts': parts.map((part) => part.toJson()).toList(),
      'timestamp': timestamp?.toIso8601String(),
    };
  }

  ChatMessage copyWith({
    String? id,
    String? role,
    List<MessagePart>? parts,
    DateTime? timestamp,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      parts: parts ?? this.parts,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Helper to get all text content concatenated
  String get textContent {
    return parts.whereType<TextPart>().map((part) => part.text).join('');
  }

  /// Helper to get all tool parts
  List<ToolPart> get toolParts {
    return parts.whereType<ToolPart>().toList();
  }

  @override
  List<Object?> get props => [id, role, parts, timestamp];
}

/// Request DTO for the chat API
/// Uses simplified format for Vercel AI SDK: {role, content}
class ChatRequest extends Equatable {
  final List<ChatMessage> messages;

  const ChatRequest({required this.messages});

  Map<String, dynamic> toJson() {
    // Convert to simplified format expected by Vercel AI SDK
    return {
      'messages': messages.map((msg) => <String, String>{
        'role': msg.role,
        'content': msg.textContent, // Extract text content only
      }).toList(),
    };
  }

  @override
  List<Object?> get props => [messages];
}

/// Conversation events for the stream
sealed class ConversationEvent extends Equatable {
  const ConversationEvent();
}

/// New message part received
class MessagePartReceived extends ConversationEvent {
  final String messageId;
  final MessagePart part;

  const MessagePartReceived({required this.messageId, required this.part});

  @override
  List<Object?> get props => [messageId, part];
}

/// Text delta received (streaming text)
class TextDeltaReceived extends ConversationEvent {
  final String messageId;
  final String delta;

  const TextDeltaReceived({required this.messageId, required this.delta});

  @override
  List<Object?> get props => [messageId, delta];
}

/// Tool call updated
class ToolCallUpdated extends ConversationEvent {
  final String messageId;
  final ToolPart toolPart;

  const ToolCallUpdated({required this.messageId, required this.toolPart});

  @override
  List<Object?> get props => [messageId, toolPart];
}

/// Stream completed
class StreamCompleted extends ConversationEvent {
  final String messageId;

  const StreamCompleted({required this.messageId});

  @override
  List<Object?> get props => [messageId];
}

/// Stream error
class StreamError extends ConversationEvent {
  final String error;
  final String? messageId;

  const StreamError({required this.error, this.messageId});

  @override
  List<Object?> get props => [error, messageId];
}

/// Tool result models for specific tools

/// SharePoint search result
class SharePointResult extends Equatable {
  final String text;
  final String source;
  final String title;
  final String site;
  final String lastModified;
  final double score;
  final String? documentViewerUrl;

  const SharePointResult({
    required this.text,
    required this.source,
    required this.title,
    required this.site,
    required this.lastModified,
    required this.score,
    this.documentViewerUrl,
  });

  factory SharePointResult.fromJson(Map<String, dynamic> json) {
    return SharePointResult(
      text: json['text'] as String,
      source: json['source'] as String,
      title: json['title'] as String,
      site: json['site'] as String,
      lastModified: json['lastModified'] as String,
      score: (json['score'] as num).toDouble(),
      documentViewerUrl: json['documentViewerUrl'] as String?,
    );
  }

  @override
  List<Object?> get props => [
    text,
    source,
    title,
    site,
    lastModified,
    score,
    documentViewerUrl,
  ];
}

/// SharePoint search response
class SharePointSearchResponse extends Equatable {
  final List<SharePointResult> results;
  final int totalResults;
  final String query;
  final String queryLanguage;
  final Map<String, dynamic> languageInfo;
  final String message;

  const SharePointSearchResponse({
    required this.results,
    required this.totalResults,
    required this.query,
    required this.queryLanguage,
    required this.languageInfo,
    required this.message,
  });

  factory SharePointSearchResponse.fromJson(Map<String, dynamic> json) {
    final resultsList = json['results'] as List<dynamic>? ?? [];
    return SharePointSearchResponse(
      results: resultsList
          .map(
            (result) =>
                SharePointResult.fromJson(result as Map<String, dynamic>),
          )
          .toList(),
      totalResults: json['totalResults'] as int,
      query: json['query'] as String,
      queryLanguage: json['queryLanguage'] as String,
      languageInfo: json['languageInfo'] as Map<String, dynamic>,
      message: json['message'] as String,
    );
  }

  @override
  List<Object?> get props => [
    results,
    totalResults,
    query,
    queryLanguage,
    languageInfo,
    message,
  ];
}

/// Site content result (events, jobs, etc.)
class SiteContentResult extends Equatable {
  final String text;
  final String source;
  final String title;
  final String type; // 'event', 'job', etc.
  final String? url;
  final double score;

  const SiteContentResult({
    required this.text,
    required this.source,
    required this.title,
    required this.type,
    this.url,
    required this.score,
  });

  factory SiteContentResult.fromJson(Map<String, dynamic> json) {
    return SiteContentResult(
      text: json['text'] as String? ?? '',
      source: json['source'] as String? ?? '',
      title: json['title'] as String? ?? '',
      type: json['type'] as String? ?? 'content',
      url: json['url'] as String?,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  List<Object?> get props => [text, source, title, type, url, score];
}

/// Site content search response
class SiteContentSearchResponse extends Equatable {
  final List<SiteContentResult> results;
  final int totalResults;
  final String query;
  final String message;

  const SiteContentSearchResponse({
    required this.results,
    required this.totalResults,
    required this.query,
    required this.message,
  });

  factory SiteContentSearchResponse.fromJson(Map<String, dynamic> json) {
    final resultsList = json['results'] as List<dynamic>? ?? [];
    return SiteContentSearchResponse(
      results: resultsList
          .map(
            (result) =>
                SiteContentResult.fromJson(result as Map<String, dynamic>),
          )
          .toList(),
      totalResults: json['totalResults'] as int? ?? resultsList.length,
      query: json['query'] as String? ?? '',
      message: json['message'] as String? ?? '',
    );
  }

  @override
  List<Object?> get props => [results, totalResults, query, message];
}

/// Document stats response
class DocumentStatsResponse extends Equatable {
  final int totalDocuments;
  final int totalChunks;
  final String message;

  const DocumentStatsResponse({
    required this.totalDocuments,
    required this.totalChunks,
    required this.message,
  });

  factory DocumentStatsResponse.fromJson(Map<String, dynamic> json) {
    return DocumentStatsResponse(
      totalDocuments: json['totalDocuments'] as int,
      totalChunks: json['totalChunks'] as int,
      message: json['message'] as String,
    );
  }

  @override
  List<Object?> get props => [totalDocuments, totalChunks, message];
}

/// SharePoint site
class SharePointSite extends Equatable {
  final String id;
  final String name;
  final String displayName;
  final String webUrl;

  const SharePointSite({
    required this.id,
    required this.name,
    required this.displayName,
    required this.webUrl,
  });

  factory SharePointSite.fromJson(Map<String, dynamic> json) {
    return SharePointSite(
      id: json['id'] as String,
      name: json['name'] as String,
      displayName: json['displayName'] as String,
      webUrl: json['webUrl'] as String,
    );
  }

  @override
  List<Object?> get props => [id, name, displayName, webUrl];
}

/// SharePoint sites response
class SharePointSitesResponse extends Equatable {
  final List<SharePointSite> sites;
  final int totalSites;
  final String message;

  const SharePointSitesResponse({
    required this.sites,
    required this.totalSites,
    required this.message,
  });

  factory SharePointSitesResponse.fromJson(Map<String, dynamic> json) {
    final sitesList = json['sites'] as List<dynamic>? ?? [];
    return SharePointSitesResponse(
      sites: sitesList
          .map((site) => SharePointSite.fromJson(site as Map<String, dynamic>))
          .toList(),
      totalSites: json['totalSites'] as int,
      message: json['message'] as String,
    );
  }

  @override
  List<Object?> get props => [sites, totalSites, message];
}

/// Weather response
class WeatherResponse extends Equatable {
  final String location;
  final String temperature;

  const WeatherResponse({required this.location, required this.temperature});

  factory WeatherResponse.fromJson(Map<String, dynamic> json) {
    return WeatherResponse(
      location: json['location'] as String,
      temperature: json['temperature'] as String,
    );
  }

  @override
  List<Object?> get props => [location, temperature];
}
