import 'dart:convert';

import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/auth_service.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/notification/inbox_opened_items_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuthService extends AuthService {
  @override
  Future<UserModel?> getCurrentUser() async => null;
}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier() : super(_FakeAuthService());

  void signIn(String id) {
    state = AuthState(
      user: UserModel(id: id, name: id, email: '$id@bi.no'),
      isAuthenticated: true,
      hasProfile: true,
    );
  }

  void endSession() => state = const AuthState();
}

Future<InboxOpenedItemsNotifier> _loaded(String? userId) async {
  final notifier = InboxOpenedItemsNotifier(userId: userId);
  addTearDown(notifier.dispose);
  await notifier.loaded;
  return notifier;
}

Future<Map<String, dynamic>> _stored(String userId) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('inbox_opened_items_$userId');
  return raw == null ? {} : jsonDecode(raw) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
    'markOpened is remembered, stored, and read back on the next start',
    () async {
      final first = await _loaded('u1');
      expect(first.openedFor('a1'), isEmpty);

      await first.markOpened('a1', 'e1');
      await first.markOpened('a1', 'e2');
      await first.markOpened('a2', 'n1');
      expect(first.openedFor('a1'), {'e1', 'e2'});
      expect(first.state.openedFor('a2'), {'n1'});

      expect(await _stored('u1'), {
        'a1': ['e1', 'e2'],
        'a2': ['n1'],
      });

      final next = await _loaded('u1');
      expect(next.openedFor('a1'), {'e1', 'e2'});
      expect(next.openedFor('a2'), {'n1'});
    },
  );

  test('opening the same item twice stores it once', () async {
    final notifier = await _loaded('u1');
    await notifier.markOpened('a1', 'e1');
    await notifier.markOpened('a1', 'e1');
    expect(await _stored('u1'), {
      'a1': ['e1'],
    });
  });

  test("one student's opened items never show for another", () async {
    final u1 = await _loaded('u1');
    await u1.markOpened('a1', 'e1');

    final u2 = await _loaded('u2');
    expect(u2.openedFor('a1'), isEmpty);
    await u2.markOpened('a1', 'e3');

    expect(await _stored('u1'), {
      'a1': ['e1'],
    });
    expect(await _stored('u2'), {
      'a1': ['e3'],
    });
  });

  test('signed out, opened items are kept in memory only', () async {
    final notifier = await _loaded(null);
    await notifier.markOpened('a1', 'e1');
    expect(notifier.openedFor('a1'), {'e1'});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });

  test('keeps the 200 most recently touched announcements', () async {
    final notifier = await _loaded('u1');
    for (var i = 0; i < 200; i++) {
      await notifier.markOpened('a$i', 'x');
    }
    // Touching a0 again makes a1 the oldest.
    await notifier.markOpened('a0', 'y');
    await notifier.markOpened('a200', 'x');

    expect(notifier.openedFor('a0'), {'x', 'y'});
    expect(notifier.openedFor('a1'), isEmpty);
    expect(notifier.openedFor('a200'), {'x'});

    final stored = await _stored('u1');
    expect(stored, hasLength(200));
    expect(stored.containsKey('a1'), isFalse);

    final reloaded = await _loaded('u1');
    expect(reloaded.openedFor('a1'), isEmpty);
    expect(reloaded.openedFor('a2'), {'x'});
  });

  test('a corrupt stored value starts empty instead of throwing', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'inbox_opened_items_u1': 'not json',
    });
    final notifier = await _loaded('u1');
    expect(notifier.openedFor('a1'), isEmpty);
    await notifier.markOpened('a1', 'e1');
    expect(await _stored('u1'), {
      'a1': ['e1'],
    });
  });

  test('the provider follows the signed-in student', () async {
    final auth = _TestAuthNotifier();
    final container = ProviderContainer(
      overrides: [authStateProvider.overrideWith((ref) => auth)],
    );
    addTearDown(container.dispose);
    // Keep the provider alive across rebuilds.
    container.listen(inboxOpenedItemsProvider, (_, _) {});
    // Let the notifier's own start-up session check (none) finish first.
    await pumpEventQueue();

    auth.signIn('u1');
    await container.read(inboxOpenedItemsProvider.notifier).loaded;
    await container
        .read(inboxOpenedItemsProvider.notifier)
        .markOpened('a1', 'e1');
    expect(container.read(inboxOpenedItemsProvider).openedFor('a1'), {'e1'});

    auth.signIn('u2');
    await container.read(inboxOpenedItemsProvider.notifier).loaded;
    expect(container.read(inboxOpenedItemsProvider).openedFor('a1'), isEmpty);

    auth.endSession();
    await container.read(inboxOpenedItemsProvider.notifier).loaded;
    expect(container.read(inboxOpenedItemsProvider).openedFor('a1'), isEmpty);

    auth.signIn('u1');
    await container.read(inboxOpenedItemsProvider.notifier).loaded;
    expect(container.read(inboxOpenedItemsProvider).openedFor('a1'), {'e1'});
  });
}
