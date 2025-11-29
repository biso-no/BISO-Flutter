import 'package:appwrite/appwrite.dart';
import 'dart:async';
import 'dart:io';

import '../../core/constants/app_constants.dart';
import '../models/chat_model.dart';
import '../models/public_profile_model.dart';
import 'appwrite_service.dart';
import 'public_profile_service.dart';

class ChatService {
  RealtimeSubscription? _subscription;
  final StreamController<List<ChatModel>> _chatsController =
      StreamController<List<ChatModel>>.broadcast();
  final StreamController<List<ChatMessageModel>> _messagesController =
      StreamController<List<ChatMessageModel>>.broadcast();

  Realtime get _realtime => realtime;
  Storage get _storage => storage;

  Stream<List<ChatModel>> get chatsStream => _chatsController.stream;
  Stream<List<ChatMessageModel>> get messagesStream =>
      _messagesController.stream;

  // Get user's chats
  Future<List<ChatModel>> getUserChats(String userId) async {
    try {
      final documents = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: 'chats',
        queries: [
          'contains("participants", "$userId")',
          'equal("is_active", true)',
          'orderDesc("last_activity_at")',
        ],
      );

      final chats = documents.rows.map((doc) => ChatModel.fromMap(doc.data)).toList();

      _chatsController.add(chats);
      return chats;
    } on AppwriteException catch (e) {
      throw ChatException('Failed to fetch chats: ${e.message}');
    } catch (e) {
      throw ChatException('Network error occurred');
    }
  }

  // Get messages for a specific chat
  Future<List<ChatMessageModel>> getChatMessages({
    required String chatId,
    int limit = AppConstants.defaultPageSize,
    String? offset,
  }) async {
    try {
      List<String> queries = [
        'equal("chat_id", "$chatId")',
        'orderDesc("timestamp")',
        'limit($limit)',
      ];

      if (offset != null) {
        queries.add('cursorAfter("$offset")');
      }

      final documents = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: 'chat_messages',
        queries: queries,
      );

      return documents.rows
          .map((doc) => ChatMessageModel.fromMap(doc.data))
          .toList()
          .reversed // Reverse to show oldest first
          .toList();
    } on AppwriteException catch (e) {
      throw ChatException('Failed to fetch messages: ${e.message}');
    } catch (e) {
      throw ChatException('Network error occurred');
    }
  }

  // Send a message
  Future<ChatMessageModel> sendMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String content,
    String type = 'text',
    List<String> attachments = const [],
    String? replyToId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final messageData = {
        'chat_id': chatId,
        'sender_id': senderId,
        'sender_name': senderName,
        'content': content,
        'type': type,
        'attachments': attachments,
        'reply_to_id': replyToId,
        'timestamp': DateTime.now().toIso8601String(),
        'is_edited': false,
        'is_deleted': false,
        'reactions': [],
        'metadata': metadata ?? {},
      };

      final doc = await db.createRow(
        databaseId: AppConstants.databaseId,
        tableId: 'chat_messages',
        rowId: ID.unique(),
        data: messageData,
      );

      final message = ChatMessageModel.fromMap(doc.data);

      // Update chat's last message and activity
      await _updateChatLastMessage(chatId, message);

      return message;
    } on AppwriteException catch (e) {
      throw ChatException('Failed to send message: ${e.message}');
    } catch (e) {
      throw ChatException('Network error occurred');
    }
  }

  // Create a new chat (always creates a team)
  Future<ChatModel> createChat({
    required String name,
    required List<String> participants,
    required String createdBy,
    String type = 'group',
    String? description,
    String? existingTeamId,
    String? departmentId,
  }) async {
    try {
      // Create team for this chat (unless existing team provided)
      final teamId =
          existingTeamId ??
          await _createChatTeam(
            chatName: name,
            participants: participants,
            createdBy: createdBy,
          );

      final chatData = {
        'name': name,
        'description': description,
        'type': type,
        'participants': participants,
        'team_id': teamId,
        'department_id': departmentId,
        'is_active': true,
        'is_muted': false,
        'unread_count': 0,
        'created_by': createdBy,
        'metadata': {
          'team_based_permissions': true,
          'auto_team_created': existingTeamId == null,
        },
        'last_activity_at': DateTime.now().toIso8601String(),
      };

      final doc = await db.createRow(
        databaseId: AppConstants.databaseId,
        tableId: 'chats',
        rowId: ID.unique(),
        data: chatData,
      );

      return ChatModel.fromMap(doc.data);
    } on AppwriteException catch (e) {
      throw ChatException('Failed to create chat: ${e.message}');
    } catch (e) {
      throw ChatException('Network error occurred');
    }
  }

  // Start real-time subscription for chats and messages
  void subscribeToUpdates(String userId) {
    try {
      _subscription = _realtime.subscribe([
        'databases.${AppConstants.databaseId}.collections.chats.documents',
        'databases.${AppConstants.databaseId}.collections.chat_messages.documents',
        'databases.${AppConstants.databaseId}.collections.typing_indicators.documents',
      ]);

      _subscription!.stream.listen((response) {
        final payload = response.payload;

        if (response.channels.contains(
          'databases.${AppConstants.databaseId}.collections.chat_messages.documents',
        )) {
          _handleMessageUpdate(payload);
        } else if (response.channels.contains(
          'databases.${AppConstants.databaseId}.collections.chats.documents',
        )) {
          _handleChatUpdate(payload, userId);
        } else if (response.channels.contains(
          'databases.${AppConstants.databaseId}.collections.typing_indicators.documents',
        )) {
          _handleTypingUpdate(payload);
        }
      });
    } catch (e) {
      throw ChatException('Failed to subscribe to updates: $e');
    }
  }

  // Add user to chat (adds to both chat and team)
  Future<void> addUserToChat(String chatId, String userId) async {
    try {
      final chat = await db.getRow(
        databaseId: AppConstants.databaseId,
        tableId: 'chats',
        rowId: chatId,
      );

      final participants = List<String>.from(chat.data['participants']);
      final teamId = chat.data['team_id'];

      if (!participants.contains(userId)) {
        participants.add(userId);

        // Update chat participants
        await db.updateRow(
          databaseId: AppConstants.databaseId,
          tableId: 'chats',
          rowId: chatId,
          data: {'participants': participants},
        );

        // Update team members if team exists
        if (teamId != null) {
          await _addUserToTeam(teamId, userId);
        }
      }
    } on AppwriteException catch (e) {
      throw ChatException('Failed to add user to chat: ${e.message}');
    } catch (e) {
      throw ChatException('Network error occurred');
    }
  }

  // Add user to team
  Future<void> _addUserToTeam(String teamId, String userId) async {
    try {
      final team = await db.getRow(
        databaseId: AppConstants.databaseId,
        tableId: 'teams',
        rowId: teamId,
      );

      final members = List<String>.from(team.data['members']);
      if (!members.contains(userId)) {
        members.add(userId);

        await db.updateRow(
          databaseId: AppConstants.databaseId,
          tableId: 'teams',
          rowId: teamId,
          data: {'members': members, 'total': members.length},
        );
      }
    } catch (e) {
      throw ChatException('Failed to add user to team: $e');
    }
  }

  // Remove user from chat (removes from both chat and team)
  Future<void> removeUserFromChat(String chatId, String userId) async {
    try {
      final chat = await db.getRow(
        databaseId: AppConstants.databaseId,
        tableId: 'chats',
        rowId: chatId,
      );

      final participants = List<String>.from(chat.data['participants']);
      final teamId = chat.data['team_id'];

      participants.remove(userId);

      // Update chat participants
      await db.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: 'chats',
        rowId: chatId,
        data: {'participants': participants},
      );

      // Remove from team if team exists
      if (teamId != null) {
        await _removeUserFromTeam(teamId, userId);
      }
    } on AppwriteException catch (e) {
      throw ChatException('Failed to remove user from chat: ${e.message}');
    } catch (e) {
      throw ChatException('Network error occurred');
    }
  }

  // Remove user from team
  Future<void> _removeUserFromTeam(String teamId, String userId) async {
    try {
      final team = await db.getRow(
        databaseId: AppConstants.databaseId,
        tableId: 'teams',
        rowId: teamId,
      );

      final members = List<String>.from(team.data['members']);
      members.remove(userId);

      await db.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: 'teams',
        rowId: teamId,
        data: {'members': members, 'total': members.length},
      );
    } catch (e) {
      throw ChatException('Failed to remove user from team: $e');
    }
  }

  // Mark messages as read
  Future<void> markAsRead(String chatId, String userId) async {
    try {
      await db.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: 'chats',
        rowId: chatId,
        data: {
          'unread_count': 0,
          'metadata': {
            'last_read_by_$userId': DateTime.now().toIso8601String(),
          },
        },
      );
    } on AppwriteException catch (e) {
      throw ChatException('Failed to mark as read: ${e.message}');
    } catch (e) {
      throw ChatException('Network error occurred');
    }
  }

  // Edit message
  Future<ChatMessageModel> editMessage({
    required String messageId,
    required String newContent,
  }) async {
    try {
      final doc = await db.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: 'chat_messages',
        rowId: messageId,
        data: {
          'content': newContent,
          'is_edited': true,
          'edited_at': DateTime.now().toIso8601String(),
        },
      );

      return ChatMessageModel.fromMap(doc.data);
    } on AppwriteException catch (e) {
      throw ChatException('Failed to edit message: ${e.message}');
    } catch (e) {
      throw ChatException('Network error occurred');
    }
  }

  // Delete message
  Future<void> deleteMessage(String messageId) async {
    try {
      await db.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: 'chat_messages',
        rowId: messageId,
        data: {'is_deleted': true, 'content': 'This message has been deleted'},
      );
    } on AppwriteException catch (e) {
      throw ChatException('Failed to delete message: ${e.message}');
    } catch (e) {
      throw ChatException('Network error occurred');
    }
  }

  // Add reaction to message
  Future<void> addReaction({
    required String messageId,
    required String emoji,
    required String userId,
    required String userName,
  }) async {
    try {
      final message = await db.getRow(
        databaseId: AppConstants.databaseId,
        tableId: 'chat_messages',
        rowId: messageId,
      );

      final reactions = List<Map<String, dynamic>>.from(
        message.data['reactions'] ?? [],
      );

      // Remove existing reaction from same user with same emoji
      reactions.removeWhere(
        (r) => r['user_id'] == userId && r['emoji'] == emoji,
      );

      // Add new reaction
      reactions.add({
        'emoji': emoji,
        'user_id': userId,
        'user_name': userName,
        'timestamp': DateTime.now().toIso8601String(),
      });

      await db.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: 'chat_messages',
        rowId: messageId,
        data: {'reactions': reactions},
      );
    } on AppwriteException catch (e) {
      throw ChatException('Failed to add reaction: ${e.message}');
    } catch (e) {
      throw ChatException('Network error occurred');
    }
  }

  // Search messages
  Future<List<ChatMessageModel>> searchMessages({
    required String chatId,
    required String query,
    int limit = 20,
  }) async {
    try {
      final response = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: 'chat_messages',
        queries: [
          Query.equal('chat_id', chatId),
          Query.search('content', query),
          Query.orderDesc('timestamp'),
          Query.limit(limit),
        ],
      );

      return response.rows
          .map((doc) => ChatMessageModel.fromMap(doc.data))
          .toList();
    } on AppwriteException catch (e) {
      throw ChatException('Failed to search messages: ${e.message}');
    } catch (e) {
      throw ChatException('Network error occurred');
    }
  }

  // Private helper methods
  Future<void> _updateChatLastMessage(
    String chatId,
    ChatMessageModel message,
  ) async {
    try {
      await db.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: 'chats',
        rowId: chatId,
        data: {
          'last_message': message.toMap(),
          'last_activity_at': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      // Don't throw, as this is a secondary operation
      // Failed to update last message: $e
    }
  }

  void _handleMessageUpdate(Map<String, dynamic> payload) {
    try {
      final message = ChatMessageModel.fromMap(payload);
      // For now, we'll just add a single message as a list
      // In a full implementation, you'd maintain the current list and add to it
      _messagesController.add([message]);
    } catch (e) {
      // Error handling message update: $e
    }
  }

  void _handleChatUpdate(Map<String, dynamic> payload, String userId) {
    try {
      final chat = ChatModel.fromMap(payload);
      if (chat.participants.contains(userId)) {
        // Refresh chats list
        getUserChats(userId);
      }
    } catch (e) {
      // Error handling chat update: $e
    }
  }

  void _handleTypingUpdate(Map<String, dynamic> payload) {
    try {
      // Handle typing indicator updates
      // This could trigger UI updates for typing indicators
      // For now, we'll just log it or handle it in the UI layer
    } catch (e) {
      // Error handling typing update: $e
    }
  }

  // Create group chat (with team)
  Future<ChatModel> createGroupChat({
    required String name,
    required List<String> participants,
    required String createdBy,
    String? description,
  }) async {
    try {
      return await createChat(
        name: name,
        participants: participants,
        createdBy: createdBy,
        type: 'group',
        description: description,
      );
    } catch (e) {
      throw Exception('Failed to create group chat: $e');
    }
  }

  // Create marketplace chat with product context
  Future<ChatModel> createMarketplaceChat({
    required String buyerId,
    required String buyerName,
    required String sellerId,
    required String sellerName,
    required String productId,
    required String productName,
    required String productImageUrl,
    required double productPrice,
    required String userMessage,
  }) async {
    try {
      final participants = [buyerId, sellerId];

      // Check if direct chat already exists between these participants
      final existingChats = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: 'chats',
        queries: [
          Query.equal('type', 'direct'),
          Query.contains('participants', buyerId),
          Query.contains('participants', sellerId),
        ],
      );

      ChatModel chat;
      if (existingChats.rows.isNotEmpty) {
        chat = ChatModel.fromMap(existingChats.rows.first.data);
      } else {
        // Create new marketplace chat with team
        chat = await createDirectChat(
          participants: participants,
          createdBy: buyerId,
        );

        // Update metadata for marketplace context
        await db.updateRow(
          databaseId: AppConstants.databaseId,
          tableId: 'chats',
          rowId: chat.id,
          data: {
            'name': 'Marketplace Chat',
            'metadata': {
              ...chat.metadata,
              'marketplace_initiated': true,
              'product_id': productId,
            },
          },
        );

        // Refresh chat data
        final updatedChat = await db.getRow(
          databaseId: AppConstants.databaseId,
          tableId: 'chats',
          rowId: chat.id,
        );
        chat = ChatModel.fromMap(updatedChat.data);
      }

      // Send combined product + user message
      await _sendMarketplaceMessage(
        chatId: chat.id,
        buyerId: buyerId,
        buyerName: buyerName,
        productId: productId,
        productName: productName,
        productImageUrl: productImageUrl,
        productPrice: productPrice,
        userMessage: userMessage,
      );

      return chat;
    } catch (e) {
      throw Exception('Failed to create marketplace chat: $e');
    }
  }

  // Create direct chat (with team for future expandability)
  Future<ChatModel> createDirectChat({
    required List<String> participants,
    required String createdBy,
  }) async {
    try {
      // Check if direct chat already exists between these participants
      final existingChats = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: 'chats',
        queries: [
          Query.equal('type', 'direct'),
          Query.contains('participants', participants[0]),
          Query.contains('participants', participants[1]),
        ],
      );

      if (existingChats.rows.isNotEmpty) {
        return ChatModel.fromMap(existingChats.rows.first.data);
      }

      // Create team for this direct chat (enables easy expansion to group chat)
      final teamId = await _createChatTeam(
        chatName: 'Direct Chat',
        participants: participants,
        createdBy: createdBy,
      );

      // Create new direct chat with team
      final chatData = {
        'name': 'Direct Chat',
        'type': 'direct',
        'participants': participants,
        'team_id': teamId,
        'is_active': true,
        'created_by': createdBy,
        'metadata': {
          'team_based_permissions': true,
          'auto_team_created': true,
          'expandable_to_group': true,
        },
        'last_activity_at': DateTime.now().toIso8601String(),
      };

      final response = await db.createRow(
        databaseId: AppConstants.databaseId,
        tableId: 'chats',
        rowId: ID.unique(),
        data: chatData,
      );

      return ChatModel.fromMap(response.data);
    } catch (e) {
      throw Exception('Failed to create direct chat: $e');
    }
  }

  // Send typing indicator
  Future<void> sendTypingIndicator(
    String chatId,
    String userId,
    String userName,
    bool isTyping,
  ) async {
    try {
      if (isTyping) {
        // Create or update typing indicator
        await db.createRow(
          databaseId: AppConstants.databaseId,
          tableId: 'typing_indicators',
          rowId: '${chatId}_$userId',
          data: {
            'chat_id': chatId,
            'user_id': userId,
            'user_name': userName,
            'is_typing': true,
            'expires_at': DateTime.now()
                .add(const Duration(seconds: 5))
                .toIso8601String(),
          },
        );
      } else {
        // Remove typing indicator
        try {
          await db.deleteRow(
            databaseId: AppConstants.databaseId,
            tableId: 'typing_indicators',
            rowId: '${chatId}_$userId',
          );
        } catch (e) {
          // Document might not exist, which is fine
        }
      }
    } catch (e) {
      // Typing indicator error: $e
    }
  }

  // React to message
  Future<void> reactToMessage({
    required String messageId,
    required String userId,
    required String userName,
    required String reaction,
  }) async {
    try {
      final message = await db.getRow(
        databaseId: AppConstants.databaseId,
        tableId: 'chat_messages',
        rowId: messageId,
      );

      final reactions = List<Map<String, dynamic>>.from(
        message.data['reactions'] ?? [],
      );

      // Check if user already reacted with this emoji
      final existingReactionIndex = reactions.indexWhere(
        (r) => r['user_id'] == userId && r['emoji'] == reaction,
      );

      if (existingReactionIndex != -1) {
        // Remove existing reaction (toggle off)
        reactions.removeAt(existingReactionIndex);
      } else {
        // Add new reaction
        reactions.add({
          'emoji': reaction,
          'user_id': userId,
          'user_name': userName,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }

      await db.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: 'chat_messages',
        rowId: messageId,
        data: {'reactions': reactions},
      );
    } catch (e) {
      throw Exception('Failed to react to message: $e');
    }
  }

  // Mark chat as read
  Future<void> markChatAsRead(String chatId, String userId) async {
    try {
      await db.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: 'chats',
        rowId: chatId,
        data: {
          'unread_count': 0,
          'metadata': {
            'last_read_by_$userId': DateTime.now().toIso8601String(),
          },
        },
      );
    } catch (e) {
      // Mark as read error: $e
    }
  }

  // Get typing indicators for a chat
  Future<List<Map<String, dynamic>>> getTypingIndicators(String chatId) async {
    try {
      final response = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: 'typing_indicators',
        queries: [
          Query.equal('chat_id', chatId),
          Query.equal('is_typing', true),
          Query.greaterThan('expires_at', DateTime.now().toIso8601String()),
        ],
      );

      return response.rows.map((doc) => doc.data).toList();
    } catch (e) {
      return [];
    }
  }

  // Upload file for chat attachment with proper permissions
  Future<String> uploadChatFile(
    File file,
    String fileName,
    ChatModel chat,
  ) async {
    try {
      final permissions = _generateFilePermissions(chat);

      final response = await _storage.createFile(
        bucketId: 'chat_attachments',
        fileId: ID.unique(),
        file: InputFile.fromPath(path: file.path, filename: fileName),
        permissions: permissions,
      );

      return response.$id;
    } catch (e) {
      throw ChatException('Failed to upload file: $e');
    }
  }

  // Generate team-based permissions (simplified approach)
  List<String> _generateFilePermissions(ChatModel chat) {
    final permissions = <String>[];

    // All chats now use team-based permissions
    if (chat.teamId != null) {
      // Primary: Team-based permissions
      permissions.add('read("team:${chat.teamId}")');

      // Additional role-based permissions for team management
      permissions.add('read("role:team_${chat.teamId}_member")');
      permissions.add('read("role:team_${chat.teamId}_admin")');
    } else {
      // Fallback: Individual user permissions (should rarely happen with new system)
      for (final participantId in chat.participants) {
        permissions.add('read("user:$participantId")');
      }
    }

    return permissions;
  }

  // Create a team for chat participants
  Future<String> _createChatTeam({
    required String chatName,
    required List<String> participants,
    required String createdBy,
  }) async {
    try {
      // Create team with chat-specific naming
      final teamData = {
        'name': 'Chat: $chatName',
        'total': participants.length,
        'members': participants,
        'prefs': {
          'is_chat_team': true,
          'chat_created_by': createdBy,
          'auto_managed': true,
        },
      };

      final response = await db.createRow(
        databaseId: AppConstants.databaseId,
        tableId: 'teams',
        rowId: ID.unique(),
        data: teamData,
      );

      return response.$id;
    } catch (e) {
      throw ChatException('Failed to create chat team: $e');
    }
  }

  // Create team chat with team-based permissions
  Future<ChatModel> createTeamChat({
    required String name,
    required String teamId,
    required List<String> participants,
    required String createdBy,
    String? description,
  }) async {
    try {
      final chatData = {
        'name': name,
        'description': description,
        'type': 'team',
        'participants': participants,
        'team_id': teamId,
        'is_active': true,
        'created_by': createdBy,
        'last_activity_at': DateTime.now().toIso8601String(),
        'metadata': {'team_permissions_enabled': true},
      };

      final response = await db.createRow(
        databaseId: AppConstants.databaseId,
        tableId: 'chats',
        rowId: ID.unique(),
        data: chatData,
      );

      return ChatModel.fromMap(response.data);
    } catch (e) {
      throw ChatException('Failed to create team chat: $e');
    }
  }

  // Create department chat with department-based permissions
  Future<ChatModel> createDepartmentChat({
    required String name,
    required String departmentId,
    required List<String> participants,
    required String createdBy,
    String? description,
  }) async {
    try {
      final chatData = {
        'name': name,
        'description': description,
        'type': 'department',
        'participants': participants,
        'department_id': departmentId,
        'is_active': true,
        'created_by': createdBy,
        'last_activity_at': DateTime.now().toIso8601String(),
        'metadata': {'department_permissions_enabled': true},
      };

      final response = await db.createRow(
        databaseId: AppConstants.databaseId,
        tableId: 'chats',
        rowId: ID.unique(),
        data: chatData,
      );

      return ChatModel.fromMap(response.data);
    } catch (e) {
      throw ChatException('Failed to create department chat: $e');
    }
  }

  // Get file URL for viewing attachments
  String getFileUrl(String fileId) {
    return _storage
        .getFileView(bucketId: 'chat_attachments', fileId: fileId)
        .toString();
  }

  // Get file download URL
  String getFileDownloadUrl(String fileId) {
    return _storage
        .getFileDownload(bucketId: 'chat_attachments', fileId: fileId)
        .toString();
  }

  // Send message with file attachment
  Future<ChatMessageModel> sendFileMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required File file,
    required String fileName,
    String? caption,
    String? replyToId,
  }) async {
    try {
      // Get chat details for permission calculation
      final chat = await db.getRow(
        databaseId: AppConstants.databaseId,
        tableId: 'chats',
        rowId: chatId,
      );
      final chatModel = ChatModel.fromMap(chat.data);

      // Upload file first with proper permissions
      final fileId = await uploadChatFile(file, fileName, chatModel);

      // Determine message type based on file extension
      String messageType = 'file';
      final extension = fileName.toLowerCase().split('.').last;
      if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension)) {
        messageType = 'image';
      }

      // Send message with file attachment
      return await sendMessage(
        chatId: chatId,
        senderId: senderId,
        senderName: senderName,
        content: caption ?? fileName,
        type: messageType,
        attachments: [fileId],
        replyToId: replyToId,
        metadata: {
          'file_name': fileName,
          'file_size': await file.length(),
          'file_type': extension,
        },
      );
    } catch (e) {
      throw ChatException('Failed to send file message: $e');
    }
  }

  // Send marketplace message (product + user text combined)
  Future<ChatMessageModel> _sendMarketplaceMessage({
    required String chatId,
    required String buyerId,
    required String buyerName,
    required String productId,
    required String productName,
    required String productImageUrl,
    required double productPrice,
    required String userMessage,
  }) async {
    // Create a single message that contains both product info and user message
    final messageData = {
      'chat_id': chatId,
      'sender_id': buyerId,
      'sender_name': buyerName,
      'content': userMessage,
      'type': 'product',
      'attachments': [productImageUrl],
      'timestamp': DateTime.now().toIso8601String(),
      'is_edited': false,
      'is_deleted': false,
      'reactions': [],
      'metadata': {
        'product_id': productId,
        'product_name': productName,
        'product_price': productPrice,
        'product_image': productImageUrl,
        'is_marketplace_initial': true,
      },
    };

    final doc = await db.createRow(
      databaseId: AppConstants.databaseId,
      tableId: 'chat_messages',
      rowId: ID.unique(),
      data: messageData,
    );

    final message = ChatMessageModel.fromMap(doc.data);
    await _updateChatLastMessage(chatId, message);
    return message;
  }

  // Get user name by ID
  Future<String> getUserName(String userId) async {
    try {
      final user = await db.getRow(
        databaseId: AppConstants.databaseId,
        tableId: 'user',
        rowId: userId,
      );
      return user.data['name'] ?? 'Unknown User';
    } catch (e) {
      return 'Unknown User';
    }
  }

  // Get multiple user names at once
  Future<Map<String, String>> getUserNames(List<String> userIds) async {
    final userNames = <String, String>{};

    for (final userId in userIds) {
      try {
        final name = await getUserName(userId);
        userNames[userId] = name;
      } catch (e) {
        userNames[userId] = 'Unknown User';
      }
    }

    return userNames;
  }

  // Delete chat and associated team
  Future<void> deleteChat(String chatId) async {
    try {
      // Get chat details first
      final chat = await db.getRow(
        databaseId: AppConstants.databaseId,
        tableId: 'chats',
        rowId: chatId,
      );

      final teamId = chat.data['team_id'];

      // Delete the chat
      await db.deleteRow(
        databaseId: AppConstants.databaseId,
        tableId: 'chats',
        rowId: chatId,
      );

      // Delete associated team if it was auto-created for this chat
      if (teamId != null && chat.data['metadata']?['auto_team_created'] == true) {
        try {
          await db.deleteRow(
            databaseId: AppConstants.databaseId,
            tableId: 'teams',
            rowId: teamId,
          );
        } catch (e) {
          // Team deletion failed, but chat is deleted - log but don't throw
        }
      }
    } catch (e) {
      throw ChatException('Failed to delete chat: $e');
    }
  }

  // Mute/unmute chat
  Future<void> muteChat(String chatId, bool muted) async {
    try {
      await db.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: 'chats',
        rowId: chatId,
        data: {'is_muted': muted},
      );
    } catch (e) {
      throw ChatException('Failed to ${muted ? 'mute' : 'unmute'} chat: $e');
    }
  }

  // Search users by name using public profiles
  Future<List<PublicProfileModel>> searchUsers(
    String query, {
    String? campusId,
  }) async {
    try {
      if (query.trim().isEmpty) return [];

      final publicProfileService = PublicProfileService();
      return await publicProfileService.searchPublicProfiles(
        query: query,
        campusId: campusId,
        limit: 20,
      );
    } catch (e) {
      throw ChatException('Failed to search users: $e');
    }
  }

  // Get recent chat contacts (only users with public profiles)
  Future<List<PublicProfileModel>> getRecentContacts(
    String currentUserId,
  ) async {
    try {
      final documents = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: 'chats',
        queries: [
          'contains("participants", "$currentUserId")',
          'equal("is_active", true)',
          'orderDesc("last_activity_at")',
          'limit(10)',
        ],
      );

      final contacts = <String>{};
      for (final chat in documents.rows) {
        final participants = List<String>.from(chat.data['participants'] ?? []);
        for (final participant in participants) {
          if (participant != currentUserId) {
            contacts.add(participant);
          }
        }
      }

      // Get public profiles for these contacts
      final publicProfileService = PublicProfileService();
      final publicProfiles = await publicProfileService
          .getMultiplePublicProfiles(contacts.toList());

      return publicProfiles;
    } catch (e) {
      return [];
    }
  }

  // Get departments list
  Future<List<Map<String, dynamic>>> getDepartments() async {
    try {
      final documents = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: 'departments',
        queries: ['equal("active", true)', 'orderAsc("name")'],
      );

      return documents.rows.map((doc) => doc.data).toList();
    } catch (e) {
      return [];
    }
  }

  // Get teams list
  Future<List<Map<String, dynamic>>> getTeams() async {
    try {
      final documents = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: 'teams',
        queries: [
          'equal("prefs.is_chat_team", false)', // Exclude auto-created chat teams
          'orderAsc("name")',
        ],
      );

      return documents.rows.map((doc) => doc.data).toList();
    } catch (e) {
      return [];
    }
  }

  // Clean up resources
  void dispose() {
    _subscription?.close();
    _chatsController.close();
    _messagesController.close();
  }
}

class ChatException implements Exception {
  final String message;
  ChatException(this.message);

  @override
  String toString() => message;
}
