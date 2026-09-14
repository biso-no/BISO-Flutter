import 'package:biso/data/models/chat_model.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/chat_service.dart';
import 'package:biso/presentation/screens/chat/chat_conversation_screen.dart';
import 'package:biso/presentation/screens/chat/chat_list_screen.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

const _userId = 'user-1';
const _user = UserModel(id: _userId, name: 'Test Student', email: 'test@bi.no');

const _chat = ChatModel(
  id: 'chat-1',
  name: 'Marketplace conversation',
  type: 'group',
  participants: [_userId, 'seller-1', 'seller-2'],
);

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth() : super(const AuthState(isAuthenticated: true, user: _user));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// `markChatAsRead` is called from a post-frame callback on every build, and
/// `sendTypingIndicator` would fire if a test typed into the composer; both
/// are no-ops here so no real Appwrite call is ever attempted.
class _FakeChatService implements ChatService {
  @override
  Future<void> markChatAsRead(String chatId, String userId) async {}

  @override
  Future<void> sendTypingIndicator(
    String chatId,
    String userId,
    String userName,
    bool isTyping,
  ) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 30 fake messages: a long run of text messages (some from the other
/// participant, some from the current user, with and without avatars/edits),
/// a reply, a deleted message, a system message, a product message with a
/// large price, and a message reacted to by 12 users — covers every bubble
/// kind the screen renders and, per R11, a wide amount and a two-digit count
/// that must never be ellipsized.
List<ChatMessageModel> _messages() {
  final now = DateTime(2026, 9, 14, 12);
  final messages = <ChatMessageModel>[];

  for (var i = 0; i < 20; i++) {
    final fromMe = i.isEven;
    messages.add(
      ChatMessageModel(
        id: 'm$i',
        chatId: _chat.id,
        senderId: fromMe ? _userId : 'seller-1',
        senderName: fromMe ? 'Test Student' : 'Seller One',
        content: 'Message number $i about the item',
        timestamp: now.subtract(Duration(minutes: 30 - i)),
        isEdited: i == 4,
      ),
    );
  }

  messages.add(
    ChatMessageModel(
      id: 'reply',
      chatId: _chat.id,
      senderId: 'seller-1',
      senderName: 'Seller One',
      content: 'Sounds good!',
      timestamp: now.subtract(const Duration(minutes: 8)),
      replyToId: 'm0',
      replyTo: messages[0],
      reactions: const {
        '👍': [
          'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l',
        ],
      },
    ),
  );

  messages.add(
    ChatMessageModel(
      id: 'deleted',
      chatId: _chat.id,
      senderId: 'seller-1',
      senderName: 'Seller One',
      content: '',
      timestamp: now.subtract(const Duration(minutes: 7)),
      isDeleted: true,
    ),
  );

  messages.add(
    ChatMessageModel(
      id: 'system',
      chatId: _chat.id,
      senderId: 'system',
      senderName: 'System',
      content: 'Seller One joined the chat',
      type: 'system',
      timestamp: now.subtract(const Duration(minutes: 6)),
    ),
  );

  messages.add(
    ChatMessageModel(
      id: 'product',
      chatId: _chat.id,
      senderId: _userId,
      senderName: 'Test Student',
      content: 'Still available?',
      type: 'product',
      metadata: const {
        'product_name': 'Very long product name that should wrap onto two lines',
        'product_price': 12345.50,
        'product_image': '',
      },
      timestamp: now.subtract(const Duration(minutes: 5)),
    ),
  );

  return messages.reversed.toList();
}

void main() {
  testWidgets('ChatConversationScreen builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const ChatConversationScreen(chat: _chat),
      overrides: [
        authStateProvider.overrideWith((_) => _Auth()),
        chatServiceProvider.overrideWithValue(_FakeChatService()),
        chatMessagesProvider(_chat.id).overrideWith((_) => Stream.value(_messages())),
      ],
    );
  });

  testWidgets('the product price and the 12-user reaction count are not ellipsized', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const ChatConversationScreen(chat: _chat),
      textScale: 1.6,
      overrides: [
        authStateProvider.overrideWith((_) => _Auth()),
        chatServiceProvider.overrideWithValue(_FakeChatService()),
        chatMessagesProvider(_chat.id).overrideWith((_) => Stream.value(_messages())),
      ],
    );

    final price = find.text('NOK 12346');
    expect(price, findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(price).didExceedMaxLines,
      isFalse,
    );

    final count = find.text('12');
    expect(count, findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(count).didExceedMaxLines,
      isFalse,
    );
  });
}
