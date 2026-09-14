import 'dart:async';

import 'package:biso/core/theme/biso_colors.dart';
import 'package:biso/data/models/ai_chat_models.dart';
import 'package:biso/data/services/ai_chat_service.dart';
import 'package:biso/presentation/screens/ai_chat/ai_chat_screen.dart';
import 'package:biso/presentation/widgets/ai_chat/typing_indicator.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

/// A stand-in for the real, network-backed [AiChatService]. `isAuthenticated`
/// matches production (always true — the public assistant needs no login);
/// `streamChatMessages` never touches the network. By default it hands back
/// a canned, immediately-completing reply (`user-0`/`assistant-0`,
/// `user-1`/`assistant-1`, ...) so a test can drive several round trips to
/// grow real, deterministic history; [responsesOverride] lets a test replace
/// that with its own stream (e.g. one that never completes, to keep
/// `isStreaming` true) — everything stays offline and deterministic.
class _FakeAiChatService implements AiChatService {
  _FakeAiChatService({this.reply = 'Sure, here is what I found.'});

  final String reply;

  /// Set to replace the canned auto-completing reply for every subsequent
  /// call to [streamChatMessages].
  Stream<ConversationEvent>? responsesOverride;

  int _userCounter = 0;
  int _assistantCounter = 0;

  @override
  Future<bool> isAuthenticated() async => true;

  @override
  ChatMessage createUserMessage(String text) => ChatMessage(
    id: 'user-${_userCounter++}',
    role: 'user',
    parts: [TextPart(text: text)],
    timestamp: DateTime(2026, 9, 14, 12),
  );

  // These two mirror the real `AiChatService`'s pure data transforms exactly
  // (no network involved) — the streaming flow below calls them for real, so
  // a `noSuchMethod` stub isn't enough once `TextDeltaReceived` events flow.
  @override
  ChatMessage createAssistantMessage({String? id}) => ChatMessage(
    id: id ?? 'assistant-fallback',
    role: 'assistant',
    parts: const [],
    timestamp: DateTime(2026, 9, 14, 12),
  );

  @override
  ChatMessage updateMessageWithText(ChatMessage message, String textDelta) {
    final existingTextParts = message.parts.whereType<TextPart>().toList();
    final otherParts = message.parts
        .where((part) => part is! TextPart)
        .toList();

    if (existingTextParts.isEmpty) {
      return message.copyWith(parts: [...otherParts, TextPart(text: textDelta)]);
    }

    final lastTextPart = existingTextParts.last;
    final updatedTextPart = lastTextPart.copyWith(
      text: lastTextPart.text + textDelta,
    );
    final allParts = message.parts.toList();
    final lastTextIndex = allParts.lastIndexWhere((part) => part is TextPart);
    allParts[lastTextIndex] = updatedTextPart;
    return message.copyWith(parts: allParts);
  }

  @override
  Stream<ConversationEvent> streamChatMessages({
    required List<ChatMessage> messages,
    bool useSSE = true,
  }) {
    final override = responsesOverride;
    if (override != null) return override;
    final id = 'assistant-${_assistantCounter++}';
    return Stream.fromIterable([
      TextDeltaReceived(messageId: id, delta: reply),
      StreamCompleted(messageId: id),
    ]);
  }

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Types [text] into the composer and taps send, then settles. The fake's
/// default reply resolves in microtasks (no real network delay), so this
/// terminates without needing `disableAnimations`.
Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byIcon(CupertinoIcons.paperplane_fill));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('AiChatScreen builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => AiChatScreen(chatService: _FakeAiChatService()),
    );
  });

  testWidgets(
    "sending a message shows the user bubble with palette.primary fill, "
    "and the only BackdropFilter in the tree is the header's own band",
    (tester) async {
      await pumpBisoScreen(
        tester,
        AiChatScreen(chatService: _FakeAiChatService()),
      );
      await tester.pump();

      await _send(tester, 'How do I join a club?');

      final bubble = find.byKey(const ValueKey('ai-user-bubble-user-0'));
      expect(bubble, findsOneWidget);
      final decoration =
          tester.widget<Container>(bubble).decoration as BoxDecoration;
      expect(decoration.color, BisoPalette.light.primary);

      // Sending auto-scrolls the list to the bottom, which is itself a
      // scrolled position, so the header's own translucent band is expected
      // to show (one BackdropFilter, owned by `BackdropGroup`/the header).
      // Message bubbles must never carry a second one of their own (blur and
      // glass never appear inside list items, cards or grids).
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Scrollable),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'the typing indicator is static under disableAnimations, so '
    'pumpAndSettle terminates',
    (tester) async {
      tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      final controller = StreamController<ConversationEvent>();
      final fake = _FakeAiChatService()..responsesOverride = controller.stream;

      await pumpBisoScreen(tester, AiChatScreen(chatService: fake));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Tell me about BISO');
      await tester.pump();
      await tester.tap(find.byIcon(CupertinoIcons.paperplane_fill));
      await tester.pump();

      // A repeating (non-disabled) dot animation would hang this forever;
      // the scroll-to-bottom and message-entrance transitions are one-shot
      // and settle normally.
      await tester.pumpAndSettle();

      expect(find.byType(TypingIndicator), findsOneWidget);

      // Close the stream while the screen is still mounted, so the
      // `_sendMessage` loop it's suspended in resolves before the widget is
      // torn down rather than calling setState on a disposed State.
      await controller.close();
      await tester.pump();
    },
  );

  testWidgets(
    'a short user bubble hugs its content instead of spanning the row',
    (tester) async {
      for (final scale in [1.0, 1.6]) {
        await pumpBisoScreen(
          tester,
          AiChatScreen(chatService: _FakeAiChatService()),
          textScale: scale,
        );
        await tester.pump();

        await _send(tester, 'Hi');

        final rowWidth = tester.getSize(find.byType(ListView)).width;
        final bubble = find.byKey(const ValueKey('ai-user-bubble-user-0'));
        expect(bubble, findsOneWidget, reason: 'scale $scale');
        final width = tester.getSize(bubble).width;
        expect(
          width,
          lessThan(rowWidth * 0.5),
          reason:
              '"Hi" should hug its content at scale $scale — got $width of '
              'a $rowWidth-wide row',
        );

        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  group("a long conversation's newest message and the keyboard", () {
    /// Eight round trips (welcome + 8 user + 8 assistant = 17 messages, each
    /// with a full sentence) is enough to overflow one screen, the same way
    /// `chat_conversation_design_test.dart` uses 30 fake messages. The last
    /// assistant reply (`assistant-7`) is the newest message.
    Future<AiChatScreen> pumpLongConversation(
      WidgetTester tester, {
      double textScale = 1,
    }) async {
      final fake = _FakeAiChatService(
        reply:
            'Here is a longer answer so each turn takes real vertical space '
            'in the conversation and the list actually needs to scroll.',
      );
      final screen = AiChatScreen(chatService: fake);
      await pumpBisoScreen(tester, screen, textScale: textScale);
      await tester.pump();

      for (var i = 0; i < 8; i++) {
        await _send(
          tester,
          'This is message number $i, written long enough that a handful '
          'of turns will not fit on one screen.',
        );
      }

      return screen;
    }

    testWidgets(
      'A: the newest message bubble is fully visible, clear of the composer',
      (tester) async {
        await pumpLongConversation(tester);

        final newest = find.byKey(
          const ValueKey('ai-chat-message-assistant-7'),
        );
        expect(newest, findsOneWidget);
        final bubble = tester.getRect(newest);
        final header = tester.getRect(
          find.byKey(const ValueKey('biso-page-header')),
        );
        final composer = tester.getRect(
          find.byKey(const ValueKey('ai-chat-composer-chrome')),
        );

        expect(bubble.top, greaterThanOrEqualTo(header.bottom));
        expect(bubble.bottom, lessThanOrEqualTo(composer.top + 0.5));
      },
    );

    testWidgets(
      'C: with a 300pt keyboard open, the composer stays above it and the '
      'newest bubble stays clear of the composer',
      (tester) async {
        await pumpLongConversation(tester);

        final dpr = tester.view.devicePixelRatio;
        tester.view.viewInsets = FakeViewPadding(bottom: 300 * dpr);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();

        final screenHeight = tester.view.physicalSize.height / dpr;
        final composer = tester.getRect(
          find.byKey(const ValueKey('ai-chat-composer-chrome')),
        );
        expect(composer.bottom, lessThanOrEqualTo(screenHeight - 300 + 0.5));

        final newest = find.byKey(
          const ValueKey('ai-chat-message-assistant-7'),
        );
        expect(
          tester.getRect(newest).bottom,
          lessThanOrEqualTo(composer.top + 0.5),
        );
      },
    );
  });
}
