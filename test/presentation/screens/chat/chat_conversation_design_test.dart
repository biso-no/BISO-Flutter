import 'package:biso/data/models/chat_model.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/chat_service.dart';
import 'package:biso/presentation/screens/chat/chat_conversation_screen.dart';
import 'package:biso/presentation/screens/chat/chat_list_screen.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:flutter/material.dart';
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

/// `markChatAsRead` is called once, from `initState`'s post-frame callback
/// (not on every build), and `sendTypingIndicator` would fire if a test
/// typed into the composer; both are no-ops here so no real Appwrite call is
/// ever attempted.
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

/// 30 fake messages: 26 short text messages alternating sender (the oldest
/// two — `m0` from the current user, `m1` from the other participant — are
/// deliberately one-word "Hi" greetings so a too-wide bubble is easy to
/// catch), a reply, a deleted message, a system message, and a product
/// message with a large price and a 12-user reaction — covers every bubble
/// kind the screen renders and, per R11, a wide amount and a two-digit count
/// that must never be ellipsized. Ordered oldest-to-newest then reversed, so
/// `messages[0]` (key `chat-message-product`) is the newest, exactly as the
/// real (`Query.orderDesc`) message stream returns them.
List<ChatMessageModel> _messages() {
  final now = DateTime(2026, 9, 14, 12);
  final messages = <ChatMessageModel>[];

  for (var i = 0; i < 26; i++) {
    final fromMe = i.isEven;
    final shortGreeting = i < 2;
    messages.add(
      ChatMessageModel(
        id: 'm$i',
        chatId: _chat.id,
        senderId: fromMe ? _userId : 'seller-1',
        senderName: fromMe ? 'Test Student' : 'Seller One',
        content: shortGreeting ? 'Hi' : 'Message number $i about the item',
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
      timestamp: now.subtract(const Duration(minutes: 4)),
      replyToId: 'm0',
      replyTo: messages[0],
      reactions: const {
        '👍': ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l'],
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
      timestamp: now.subtract(const Duration(minutes: 3)),
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
      timestamp: now.subtract(const Duration(minutes: 2)),
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
        'product_name':
            'Very long product name that should wrap onto two lines',
        'product_price': 12345.50,
        'product_image': '',
      },
      timestamp: now.subtract(const Duration(minutes: 1)),
    ),
  );

  return messages.reversed.toList();
}

List<Override> _overrides([ChatModel chat = _chat]) => [
  authStateProvider.overrideWith((_) => _Auth()),
  chatServiceProvider.overrideWithValue(_FakeChatService()),
  chatMessagesProvider(chat.id).overrideWith((_) => Stream.value(_messages())),
];

/// The message list is a plain (non-reversed-slivers) `ListView`, not the
/// `CustomScrollView` a `slivers:` BisoPage uses, so its `Scrollable` is
/// found the same way `biso_page_test.dart` finds a CustomScrollView's.
ScrollableState _messageScrollable(WidgetTester tester) =>
    tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );

void main() {
  testWidgets('ChatConversationScreen builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const ChatConversationScreen(chat: _chat),
      overrides: _overrides(),
    );
  });

  testWidgets(
    'a short bubble from either side hugs its content instead of spanning the row',
    (tester) async {
      for (final scale in [1.0, 1.6]) {
        await pumpBisoScreen(
          tester,
          const ChatConversationScreen(chat: _chat),
          textScale: scale,
          overrides: _overrides(),
        );
        await tester.pump();

        // m0/m1 are the oldest messages, off the lazy list's initial build
        // range (which starts at the newest, bottom-anchored end); scroll
        // them into view first.
        final scrollable = _messageScrollable(tester);
        for (var i = 0; i < 6; i++) {
          scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
          await tester.pump();
        }

        final rowWidth = tester.getSize(find.byType(ListView)).width;
        for (final id in ['m0', 'm1']) {
          final bubble = find.byKey(ValueKey('chat-bubble-$id'));
          expect(bubble, findsOneWidget, reason: 'id $id, scale $scale');
          final width = tester.getSize(bubble).width;
          expect(
            width,
            lessThan(rowWidth * 0.5),
            reason:
                '"$id" ("Hi") should hug its content at scale $scale — '
                'got $width of a $rowWidth-wide row',
          );
        }
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'the compact header title is just the chat name; the member count lives '
    'at the oldest end of the history instead of being folded in and '
    'truncated',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const ChatConversationScreen(chat: _chat),
        overrides: _overrides(),
      );
      await tester.pump();

      final titleFinder = find.byKey(const ValueKey('biso-compact-title'));
      expect(titleFinder, findsOneWidget);
      final titleText = tester.widget<Text>(titleFinder).data;
      expect(titleText, _chat.name);
      expect(titleText, isNot(contains('member')));

      _messageScrollable(
        tester,
      ).position.jumpTo(_messageScrollable(tester).position.maxScrollExtent);
      await tester.pump();

      final label = find.text('3 members');
      expect(label, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
        isFalse,
      );
    },
  );

  testWidgets('a direct chat never shows a member count', (tester) async {
    const directChat = ChatModel(
      id: 'dm-1',
      name: 'Seller One',
      type: 'direct',
      participants: [_userId, 'seller-1'],
    );
    await pumpBisoScreen(
      tester,
      const ChatConversationScreen(chat: directChat),
      overrides: _overrides(directChat),
    );
    await tester.pump();

    _messageScrollable(
      tester,
    ).position.jumpTo(_messageScrollable(tester).position.maxScrollExtent);
    await tester.pump();

    expect(find.textContaining('members'), findsNothing);
  });

  group("the brief's 30-message screen test", () {
    testWidgets(
      'A: the newest bubble is fully visible, clear of the composer',
      (tester) async {
        await pumpBisoScreen(
          tester,
          const ChatConversationScreen(chat: _chat),
          overrides: _overrides(),
        );
        await tester.pump();

        final newest = find.byKey(const ValueKey('chat-message-product'));
        expect(newest, findsOneWidget);
        final bubble = tester.getRect(newest);
        final header = tester.getRect(
          find.byKey(const ValueKey('biso-page-header')),
        );
        final composer = tester.getRect(
          find.byKey(const ValueKey('chat-composer-chrome')),
        );

        expect(bubble.top, greaterThanOrEqualTo(header.bottom));
        expect(bubble.bottom, lessThanOrEqualTo(composer.top + 0.5));
      },
    );

    testWidgets(
      'B: scrolling to the oldest message passes an earlier bubble under the header',
      (tester) async {
        await pumpBisoScreen(
          tester,
          const ChatConversationScreen(chat: _chat),
          overrides: _overrides(),
        );
        await tester.pump();

        // A lazy ListView only knows the real extent of items it has built,
        // so the first jump (based on an estimate) undershoots; repeating it
        // converges once the newly-revealed items refine the real extent.
        final scrollable = _messageScrollable(tester);
        for (var i = 0; i < 6; i++) {
          scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
          await tester.pump();
        }
        // At the true max, the oldest item comes to rest with its own
        // 8pt gutter below the header (BisoPage's top clearance), the same
        // way the newest message never overlaps the composer in test A —
        // that's the point of the clearance padding. The header is a fixed
        // overlay a scroll position passes *through* on the way there, so
        // backing off from full rest catches an oldest bubble mid-transit,
        // still under the header, the same way `biso_page_test.dart`'s
        // partial (not full-extent) drag does for a plain row list.
        scrollable.position.jumpTo(scrollable.position.maxScrollExtent - 150);
        await tester.pump();

        final header = tester.getRect(
          find.byKey(const ValueKey('biso-page-header')),
        );
        final overlapsHeader = _messages().any((message) {
          final f = find.byKey(ValueKey('chat-message-${message.id}'));
          if (f.evaluate().isEmpty) return false;
          return tester.getRect(f).overlaps(header);
        });
        expect(overlapsHeader, isTrue);
      },
    );

    testWidgets(
      'C: with a 300pt keyboard open, the composer stays above it and the '
      'newest bubble stays clear of the composer',
      (tester) async {
        await pumpBisoScreen(
          tester,
          const ChatConversationScreen(chat: _chat),
          overrides: _overrides(),
        );
        await tester.pump();

        final dpr = tester.view.devicePixelRatio;
        tester.view.viewInsets = FakeViewPadding(bottom: 300 * dpr);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();

        final screenHeight = tester.view.physicalSize.height / dpr;
        final composer = tester.getRect(
          find.byKey(const ValueKey('chat-composer-chrome')),
        );
        expect(composer.bottom, lessThanOrEqualTo(screenHeight - 300 + 0.5));

        final newest = find.byKey(const ValueKey('chat-message-product'));
        expect(
          tester.getRect(newest).bottom,
          lessThanOrEqualTo(composer.top + 0.5),
        );
      },
    );
  });

  testWidgets(
    'the product price and the 12-user reaction count are not ellipsized',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const ChatConversationScreen(chat: _chat),
        textScale: 1.6,
        overrides: _overrides(),
      );

      final price = find.text('NOK 12346');
      expect(price, findsOneWidget);
      final priceParagraph = tester.renderObject<RenderParagraph>(price);
      expect(priceParagraph.didExceedMaxLines, isFalse);
      expect(
        priceParagraph.size.width,
        greaterThanOrEqualTo(
          priceParagraph.getMaxIntrinsicWidth(double.infinity) - 0.5,
        ),
      );

      final count = find.text('12');
      expect(count, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(count).didExceedMaxLines,
        isFalse,
      );
    },
  );
}
