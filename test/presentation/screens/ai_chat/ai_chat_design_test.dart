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
/// `streamChatMessages` never touches the network — it hands back a canned
/// stream so a test controls exactly what the screen sees without a real SSE
/// connection, keeping the suite offline and deterministic.
class _FakeAiChatService implements AiChatService {
  _FakeAiChatService({Stream<ConversationEvent>? responses})
    : _responses =
          responses ??
          Stream.value(const StreamCompleted(messageId: 'assistant-reply'));

  final Stream<ConversationEvent> _responses;

  @override
  Future<bool> isAuthenticated() async => true;

  @override
  ChatMessage createUserMessage(String text) => ChatMessage(
    id: 'test-user-message',
    role: 'user',
    parts: [TextPart(text: text)],
    timestamp: DateTime(2026, 9, 14, 12),
  );

  @override
  Stream<ConversationEvent> streamChatMessages({
    required List<ChatMessage> messages,
    bool useSSE = true,
  }) => _responses;

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

      await tester.enterText(find.byType(TextField), 'How do I join a club?');
      await tester.pump();

      await tester.tap(find.byIcon(CupertinoIcons.paperplane_fill));
      // The scroll-to-bottom and message-entrance transitions are one-shot,
      // so settling terminates and lands the new message in the built range.
      await tester.pumpAndSettle();

      final bubble = find.byKey(const ValueKey('ai-user-bubble'));
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

      await pumpBisoScreen(
        tester,
        AiChatScreen(
          chatService: _FakeAiChatService(responses: controller.stream),
        ),
      );
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
}
