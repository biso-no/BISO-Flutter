import 'package:biso/data/models/app_notification_model.dart';
import 'package:biso/presentation/screens/notifications/notifications_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/notification/notification_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

final _unread = AppNotification(
  id: 'n-unread',
  title: 'Campus closed tomorrow',
  body: 'Facilities will be closed for maintenance.',
  category: 'event',
  createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
);

final _read = AppNotification(
  id: 'n-read',
  title: 'Welcome to BISO',
  body: 'Thanks for joining the community.',
  category: 'general',
  createdAt: DateTime.now().subtract(const Duration(days: 2)),
  read: true,
);

/// A [NotificationInboxNotifier] double that skips the network entirely and
/// simply carries the state a test hands it. Mirrors the `_Auth` pattern used
/// throughout (e.g. profile_design_test.dart): extends the real
/// [StateNotifier] for `state`/`dispose`, and implements the notifier's own
/// interface via `noSuchMethod` so `refresh`/`load`/`markRead` - never invoked
/// by these tests, since nothing pulls to refresh or taps a row - don't need
/// real bodies.
class _FakeInbox extends StateNotifier<NotificationInboxState>
    implements NotificationInboxNotifier {
  _FakeInbox(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> _overrides(NotificationInboxState state) => [
  notificationInboxProvider.overrideWith((ref) => _FakeInbox(state)),
];

void main() {
  testWidgets('Notifications builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const NotificationsScreen(),
      inShell: false,
      overrides: _overrides(NotificationInboxState(items: [_unread, _read])),
    );
  });

  testWidgets(
    'an unread notification shows the link-colored dot; a read one does not',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const NotificationsScreen(),
        inShell: false,
        overrides: _overrides(
          NotificationInboxState(items: [_unread, _read]),
        ),
      );

      final unreadRow = tester.widget<BisoListRow>(
        find.ancestor(
          of: find.text('Campus closed tomorrow'),
          matching: find.byType(BisoListRow),
        ),
      );
      final readRow = tester.widget<BisoListRow>(
        find.ancestor(
          of: find.text('Welcome to BISO'),
          matching: find.byType(BisoListRow),
        ),
      );

      expect(unreadRow.trailing, isNotNull);
      expect(readRow.trailing, isNull);
    },
  );

  testWidgets('an empty inbox shows the empty state', (tester) async {
    await pumpBisoScreen(
      tester,
      const NotificationsScreen(),
      inShell: false,
      overrides: _overrides(const NotificationInboxState()),
    );

    expect(find.text('No notifications yet'), findsOneWidget);
  });

  testWidgets(
    'each row tells screen readers its category, as the old chip showed it',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpBisoScreen(
        tester,
        const NotificationsScreen(),
        inShell: false,
        overrides: _overrides(
          NotificationInboxState(items: [_unread, _read]),
        ),
      );

      final eventRow = tester.getSemantics(
        find.ancestor(
          of: find.text('Campus closed tomorrow'),
          matching: find.byType(BisoListRow),
        ),
      );
      final generalRow = tester.getSemantics(
        find.ancestor(
          of: find.text('Welcome to BISO'),
          matching: find.byType(BisoListRow),
        ),
      );
      expect(eventRow.label, contains('Event'));
      expect(eventRow.label, contains('Campus closed tomorrow'));
      expect(generalRow.label, contains('General'));
      semantics.dispose();
    },
  );
}
