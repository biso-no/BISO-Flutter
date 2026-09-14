import 'package:biso/data/models/chat_model.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/chat_service.dart';
import 'package:biso/presentation/screens/chat/chat_info_screen.dart';
import 'package:biso/presentation/screens/chat/chat_list_screen.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

const _userId = 'user-1';
const _user = UserModel(id: _userId, name: 'Test Student', email: 'test@bi.no');

/// A group chat owned by the current user, with a description, three
/// participants (including "you"), a mute setting off, and chat statistics —
/// exercises every section the screen renders: avatar/name/type/description,
/// the edit action (owner of a group chat), participants, settings, stats,
/// and the owner-only add/delete actions.
final _chat = ChatModel(
  id: 'chat-1',
  name: 'Study group',
  description: 'BI Oslo exam prep',
  type: 'group',
  participants: const [_userId, 'member-2', 'member-3'],
  isMuted: false,
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

  testWidgets('shows participant count, roles, "You" and the mute toggle', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      ChatInfoScreen(chat: _chat),
      overrides: _overrides(),
    );
    await tester.pump();

    expect(find.text('Participants (3)'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Member'), findsWidgets);
    expect(find.text('Mute notifications'), findsOneWidget);

    final muteSwitch = tester.widget<Switch>(find.byType(Switch));
    expect(muteSwitch.value, isFalse);
  });
}
