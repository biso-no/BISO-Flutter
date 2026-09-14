import 'package:biso/data/models/chat_model.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/chat_service.dart';
import 'package:biso/presentation/screens/chat/chat_info_screen.dart';
import 'package:biso/presentation/screens/chat/chat_list_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

const _userId = 'user-1';
const _user = UserModel(id: _userId, name: 'Test Student', email: 'test@bi.no');

/// A group chat owned by the current user, with a description, three
/// participants (including "you"), and chat statistics — exercises every
/// section the screen renders: avatar/name/type/description, the edit
/// action (owner of a group chat), participants, stats, and the owner-only
/// add/delete actions.
final _chat = ChatModel(
  id: 'chat-1',
  name: 'Study group',
  description: 'BI Oslo exam prep',
  type: 'group',
  participants: const [_userId, 'member-2', 'member-3'],
  metadata: const {'created_by': _userId, 'message_count': 42},
  createdAt: DateTime(2026, 1, 10),
  lastActivityAt: DateTime(2026, 9, 1),
);

/// A direct chat where the current user is not the owner, so the "Leave
/// Chat" destructive row (rather than add/delete) renders.
const _memberChat = ChatModel(
  id: 'chat-2',
  name: 'Team channel',
  type: 'team',
  participants: [_userId, 'owner-1'],
  metadata: {'created_by': 'owner-1'},
);

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth() : super(const AuthState(isAuthenticated: true, user: _user));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// `getUserNames` is called once from `initState`'s `_loadUserNames`; the
/// other members are never invoked by a plain build, so they are left to
/// `noSuchMethod`.
class _FakeChatService implements ChatService {
  @override
  Future<Map<String, String>> getUserNames(List<String> userIds) async => {
    for (final id in userIds) id: 'Member $id',
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> _overrides() => [
  authStateProvider.overrideWith((_) => _Auth()),
  chatServiceProvider.overrideWithValue(_FakeChatService()),
];

void main() {
  testWidgets(
    'ChatInfoScreen builds on BisoPage in every appearance (owner view)',
    (tester) async {
      await expectBuildsCleanly(
        tester,
        () => ChatInfoScreen(chat: _chat),
        overrides: _overrides(),
      );
    },
  );

  testWidgets(
    'ChatInfoScreen builds on BisoPage in every appearance (member view)',
    (tester) async {
      await expectBuildsCleanly(
        tester,
        () => const ChatInfoScreen(chat: _memberChat),
        overrides: _overrides(),
      );
    },
  );

  testWidgets(
    'shows the Type heading, participant count, roles, and "You"',
    (tester) async {
      await pumpBisoScreen(
        tester,
        ChatInfoScreen(chat: _chat),
        overrides: _overrides(),
      );
      await tester.pump();

      expect(find.text('Type'), findsOneWidget);
      expect(find.text('Group Chat'), findsOneWidget);
      expect(find.text('Participants (3)'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('Member'), findsWidgets);
    },
  );

  testWidgets(
    'shows the message count in full, never ellipsized (R11)',
    (tester) async {
      await pumpBisoScreen(
        tester,
        ChatInfoScreen(chat: _chat),
        textScale: 1.6,
        overrides: _overrides(),
      );
      await tester.pump();

      // At this text scale the Chat Statistics section sits past the
      // viewport's initial cache extent; scroll it into range first (same
      // approach as biso_page_test.dart's plain-row-list drag).
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pump();

      final count = find.text('42');
      expect(count, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(count).didExceedMaxLines,
        isFalse,
      );
    },
  );

  testWidgets(
    'editing shows the name and description fields, scroll-padded past the '
    'header — proving the Builder+BisoPageInsets path is used',
    (tester) async {
      await pumpBisoScreen(
        tester,
        ChatInfoScreen(chat: _chat),
        overrides: _overrides(),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Edit chat'));
      await tester.pump();

      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields, hasLength(2));
      for (final field in fields) {
        expect(
          field.scrollPadding.top,
          greaterThanOrEqualTo(47 + kBisoHeaderHeight),
        );
      }
    },
  );
}
