import 'package:biso/data/models/app_notification_model.dart';
import 'package:biso/data/models/inbox_item.dart';
import 'package:biso/presentation/screens/notifications/notifications_screen.dart';
import 'package:biso/providers/notification/inbox_opened_items_provider.dart';
import 'package:biso/providers/notification/notification_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/biso_screen_harness.dart';

final _now = DateTime(2026, 10, 20, 12);

AppNotification _n(
  String id,
  String title, {
  String category = 'general',
  String? contentType,
  Duration age = const Duration(hours: 1),
  List<InboxItem> items = const [],
}) => AppNotification(
  id: id,
  title: title,
  body: '',
  category: category,
  contentType: contentType,
  createdAt: _now.subtract(age),
  items: items,
);

/// The inbox, holding [state]; [clear] records each call's ids and takes them
/// out at once, then puts them back when [clearSucceeds] is false.
class _FakeInbox extends StateNotifier<NotificationInboxState>
    implements NotificationInboxNotifier {
  _FakeInbox(List<AppNotification> items)
    : super(NotificationInboxState(items: items));

  final clears = <List<String>>[];
  bool clearSucceeds = true;

  @override
  Future<bool> clear(Iterable<String> announcementIds) async {
    final ids = announcementIds.toList();
    clears.add(ids);
    final before = state.items;
    state = NotificationInboxState(
      items: [
        for (final n in before)
          if (!ids.contains(n.id)) n,
      ],
    );
    await Future<void>.delayed(Duration.zero);
    if (!clearSucceeds) state = NotificationInboxState(items: before);
    return clearSucceeds;
  }

  @override
  Future<void> markRead(AppNotification notification) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeInbox> _pump(
  WidgetTester tester,
  List<AppNotification> items, {
  Locale? locale,
}) async {
  final inbox = _FakeInbox(items);
  await pumpBisoScreen(
    tester,
    NotificationsScreen(clock: () => _now),
    inShell: false,
    locale: locale,
    overrides: [
      notificationInboxProvider.overrideWith((ref) => inbox),
      inboxOpenedItemsProvider.overrideWith(
        (ref) => InboxOpenedItemsNotifier(userId: 'u1'),
      ),
    ],
  );
  return inbox;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  final mixed = [
    _n('e1', 'Quiz night', contentType: 'event'),
    _n('n1', 'Campus news', contentType: 'news', age: const Duration(hours: 2)),
    _n('u1', 'Fire drill', category: 'urgent', age: const Duration(hours: 3)),
  ];

  /// Taps the filter chip labelled [label], scrolling it out from under the
  /// "Clear all" link first.
  Future<void> tapChip(WidgetTester tester, String label) async {
    final chip = find.widgetWithText(ChoiceChip, label);
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  Future<void> selectEvents(WidgetTester tester) => tapChip(tester, 'Events');

  testWidgets('swiping a row right to left clears it', (tester) async {
    final inbox = await _pump(tester, [_n('a', 'Fresh note')]);

    await tester.drag(find.text('Fresh note'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(inbox.clears, [
      ['a'],
    ]);
    expect(find.text('Fresh note'), findsNothing);
  });

  testWidgets('swiping left to right does nothing', (tester) async {
    final inbox = await _pump(tester, [_n('a', 'Fresh note')]);

    await tester.drag(find.text('Fresh note'), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(inbox.clears, isEmpty);
    expect(find.text('Fresh note'), findsOneWidget);
  });

  testWidgets('each row offers a Clear action to screen readers, on the '
      'row itself', (tester) async {
    final handle = tester.ensureSemantics();
    final inbox = await _pump(tester, [_n('a', 'Fresh note')]);
    const clear = CustomSemanticsAction(label: 'Clear');

    // The node VoiceOver and TalkBack read out as the row carries the action:
    // no separate, unlabeled stop holds it.
    expect(
      tester.getSemantics(find.text('Fresh note')),
      isSemantics(customActions: [clear]),
    );
    tester.semantics.customAction(
      find.semantics.byAction(SemanticsAction.customAction),
      clear,
    );
    await tester.pumpAndSettle();

    expect(inbox.clears, [
      ['a'],
    ]);
    handle.dispose();
  });

  testWidgets('Clear all under a filter clears only the rows on screen, '
      'pinned urgent rows included, after confirming', (tester) async {
    final inbox = await _pump(tester, mixed);
    await selectEvents(tester);

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(find.text('Clear 2 notifications?'), findsOneWidget);
    expect(
      find.text("They're removed from your inbox on all your devices."),
      findsOneWidget,
    );
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(inbox.clears, hasLength(1));
    expect(inbox.clears.single.toSet(), {'u1', 'e1'});
    expect([for (final n in inbox.state.items) n.id], ['n1']);
  });

  testWidgets('Cancel clears nothing', (tester) async {
    final inbox = await _pump(tester, mixed);

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(inbox.clears, isEmpty);
    expect(find.text('Quiz night'), findsOneWidget);
  });

  testWidgets('Clear all is hidden when nothing is on screen', (tester) async {
    await _pump(tester, const []);
    expect(find.text('Clear all'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await _pump(tester, [_n('n1', 'Campus news', contentType: 'news')]);
    expect(find.text('Clear all'), findsOneWidget);
    await selectEvents(tester);
    expect(find.text('Clear all'), findsNothing);
  });

  testWidgets('a clear that fails says so', (tester) async {
    final inbox = await _pump(tester, [_n('a', 'Fresh note')]);
    inbox.clearSucceeds = false;

    await tester.drag(find.text('Fresh note'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't clear. Try again."), findsOneWidget);
    expect(find.text('Fresh note'), findsOneWidget);
  });

  testWidgets('Norwegian copy', (tester) async {
    await _pump(tester, mixed, locale: const Locale('no'));
    await tapChip(tester, 'Arrangementer');

    await tester.tap(find.text('Fjern alle'));
    await tester.pumpAndSettle();

    expect(find.text('Fjerne 2 varsler?'), findsOneWidget);
    expect(
      find.text('De fjernes fra innboksen på alle enhetene dine.'),
      findsOneWidget,
    );
  });

  testWidgets('dragging the burst card strip sideways scrolls it and does not '
      'clear the row', (tester) async {
    final burst = _n(
      'burst',
      'New in Bergen',
      contentType: 'event',
      items: [
        for (final i in [1, 2, 3, 4])
          InboxItem(
            type: 'event',
            id: 'e$i',
            titleEn: 'Bergen event $i',
            date: DateTime(2026, 11, i),
          ),
      ],
    );
    final inbox = await _pump(tester, [burst]);

    await tester.drag(find.text('Bergen event 1'), const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(inbox.clears, isEmpty);
    expect(find.text('New in Bergen'), findsOneWidget);
  });

  testWidgets('dragging a burst strip that fits on screen does not clear the '
      'row', (tester) async {
    final burst = _n(
      'burst',
      'Two in Bergen',
      contentType: 'event',
      items: [
        for (final i in [1, 2])
          InboxItem(
            type: 'event',
            id: 'e$i',
            titleEn: 'Bergen event $i',
            date: DateTime(2026, 11, i),
          ),
      ],
    );
    final inbox = await _pump(tester, [burst]);

    await tester.drag(find.text('Bergen event 1'), const Offset(-250, 0));
    await tester.pumpAndSettle();

    expect(inbox.clears, isEmpty);
    expect(find.text('Two in Bergen'), findsOneWidget);
  });

  testWidgets("an empty inbox says You're all caught up", (tester) async {
    await _pump(tester, const []);

    expect(find.text("You're all caught up"), findsOneWidget);
  });
}
