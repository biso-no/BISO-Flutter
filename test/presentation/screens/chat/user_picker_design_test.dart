import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/models/public_profile_model.dart';
import 'package:biso/data/services/chat_service.dart';
import 'package:biso/presentation/screens/chat/chat_list_screen.dart';
import 'package:biso/presentation/screens/chat/user_picker_screen.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

const _campus = CampusModel(
  id: 'oslo',
  name: 'Oslo',
  description: 'Test campus',
  location: 'Oslo',
  imageUrl: '',
  heroImageUrl: '',
  stats: CampusStats(),
);

const _users = [
  PublicProfileModel(
    id: 'p1',
    userId: 'user-a',
    name: 'Anna Andersen',
    email: 'anna@bi.no',
    emailVisible: true,
  ),
  PublicProfileModel(
    id: 'p2',
    userId: 'user-b',
    name: 'Bjorn Berg',
    email: 'bjorn@bi.no',
    emailVisible: true,
  ),
];

/// Filters `_users` by the query, the same way the real `searchUsers` (a
/// `PublicProfileService.searchPublicProfiles` call) narrows results — the
/// filtering itself stays server-side; this fake only stands in for it.
class _FakeChatService implements ChatService {
  @override
  Future<List<PublicProfileModel>> searchUsers(
    String query, {
    String? campusId,
  }) async {
    return _users
        .where((u) => u.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> _overrides() => [
  selectedCampusProvider.overrideWithValue(_campus),
  chatServiceProvider.overrideWithValue(_FakeChatService()),
];

void main() {
  testWidgets('UserPickerScreen builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const UserPickerScreen(),
      overrides: _overrides(),
    );
  });

  testWidgets(
    'the header search filters the fake users, and selecting one shows its chip',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const UserPickerScreen(),
        overrides: _overrides(),
      );

      // Before any query, the picker shows its "start typing" prompt, not a
      // lazily-built list of every user.
      expect(find.text('Start typing to search users'), findsOneWidget);

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      final field = find.byType(TextField);
      await tester.enterText(field, 'anna');
      await tester.pump(const Duration(milliseconds: 400)); // past debounce
      await tester.pumpAndSettle();

      expect(find.text('Anna Andersen'), findsOneWidget);
      expect(find.text('Bjorn Berg'), findsNothing);

      await tester.tap(find.text('Anna Andersen'));
      await tester.pump();

      expect(find.byType(Chip), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Chip),
          matching: find.text('Anna Andersen'),
        ),
        findsOneWidget,
      );
    },
  );
}
