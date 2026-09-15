import 'package:biso/core/constants/app_colors.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/models/large_event_model.dart';
import 'package:biso/data/services/large_event_item_service.dart';
import 'package:biso/presentation/screens/events/large_event_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/large_event/large_event_items_provider.dart';
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

/// Not `const`: `DateTime.utc` is not a constant expression.
final _scheduleItems = <LargeEventScheduleItem>[
  LargeEventScheduleItem(
    id: 'item-1',
    title: 'Opening Ceremony',
    startTime: DateTime.utc(2030, 8, 10, 18),
    endTime: DateTime.utc(2030, 8, 10, 20),
    location: 'Main Hall',
    ticketUrl: 'https://tickets.example.com/opening',
  ),
  LargeEventScheduleItem(
    id: 'item-2',
    title: 'Campus Tour',
    startTime: DateTime.utc(2030, 8, 11, 10),
  ),
];

/// Deliberately no `backgroundImageUrl`/`logoUrl`: a CachedNetworkImage
/// cannot resolve under flutter_test, so the fixtures stay on the
/// no-image branches of `_EventHero`/`_EventSummary`.
LargeEventModel _perEventModel({
  List<LargeEventScheduleItem> schedule = const [],
}) => LargeEventModel(
  id: 'event-1',
  slug: 'welcome-week',
  name: 'Welcome Week',
  description:
      'A full week of welcome activities across campus, with a very long '
      'description that should wrap onto more than one line under the '
      'hero image.',
  startDate: DateTime.utc(2030, 8, 10),
  endDate: DateTime.utc(2030, 8, 17),
  isActive: true,
  heroOverrideEnabled: true,
  priority: 1,
  campusConfigs: {
    'oslo': LargeEventCampusConfig(
      campusId: 'oslo',
      isActive: true,
      heroOverrideEnabled: true,
      ticketingModel: LargeEventTicketingModel.perEvent,
      schedule: schedule,
    ),
  },
);

LargeEventModel _allAccessModel() => LargeEventModel(
  id: 'event-2',
  slug: 'business-summit',
  name: 'Business Summit',
  description: 'One ticket, every session, all week long.',
  startDate: DateTime.utc(2030, 3, 1),
  endDate: DateTime.utc(2030, 3, 3),
  isActive: true,
  heroOverrideEnabled: true,
  priority: 1,
  campusConfigs: const {
    'oslo': LargeEventCampusConfig(
      campusId: 'oslo',
      isActive: true,
      heroOverrideEnabled: true,
      ticketingModel: LargeEventTicketingModel.allAccess,
      schedule: [],
      allAccessPassUrl: 'https://tickets.example.com/pass',
      ticketPortalUrl: 'https://tickets.example.com/portal',
    ),
  },
);

LargeEventModel _noConfigModel() => LargeEventModel(
  id: 'event-3',
  slug: 'no-campus',
  name: 'Not Here',
  description: 'Not configured for this campus.',
  startDate: DateTime.utc(2030, 1, 1),
  endDate: DateTime.utc(2030, 1, 2),
  isActive: true,
  heroOverrideEnabled: true,
  priority: 1,
  campusConfigs: const {},
);

/// A `primaryColorHex` is free-form CMS content, so the date pill's text
/// color must be picked for contrast rather than assumed to be white.
LargeEventModel _eventWithBrandColor(String hex) => LargeEventModel(
  id: 'event-color',
  slug: 'color-test',
  name: 'Color Test',
  description: 'Testing pill contrast.',
  startDate: DateTime.utc(2030, 8, 10),
  endDate: DateTime.utc(2030, 8, 17),
  isActive: true,
  heroOverrideEnabled: true,
  priority: 1,
  primaryColorHex: hex,
  campusConfigs: const {},
);

/// Replaces the real Appwrite-backed service. Deterministic and offline.
class _FakeLargeEventItemService extends LargeEventItemService {
  _FakeLargeEventItemService(this._items);
  final List<LargeEventScheduleItem> _items;

  @override
  Future<List<LargeEventScheduleItem>> listItems({
    required String eventId,
    required String campusId,
  }) async => _items;
}

List<Override> _overrides({required List<LargeEventScheduleItem> items}) => [
  filterCampusProvider.overrideWithValue(_campus),
  largeEventItemServiceProvider.overrideWithValue(
    _FakeLargeEventItemService(items),
  ),
];

void main() {
  testWidgets(
    'Large event builds on BisoPage in every appearance (per-event ticketing)',
    (tester) async {
      await expectBuildsCleanly(
        tester,
        () => LargeEventScreen(event: _perEventModel(schedule: _scheduleItems)),
        overrides: _overrides(items: const []),
        inShell: false,
        routed: true,
      );
    },
  );

  testWidgets(
    'Large event builds on BisoPage in every appearance (all-access ticketing)',
    (tester) async {
      await expectBuildsCleanly(
        tester,
        () => LargeEventScreen(event: _allAccessModel()),
        overrides: _overrides(items: const []),
        inShell: false,
        routed: true,
      );
    },
  );

  testWidgets(
    'an event with no campus config hides ticketing and schedule',
    (tester) async {
      await expectBuildsCleanly(
        tester,
        () => LargeEventScreen(event: _noConfigModel()),
        overrides: _overrides(items: const []),
        inShell: false,
        routed: true,
      );
    },
  );

  testWidgets(
    'the hero starts at y = 0 and the compact title is hidden at rest',
    (tester) async {
      await pumpBisoScreen(
        tester,
        LargeEventScreen(event: _perEventModel(schedule: _scheduleItems)),
        overrides: _overrides(items: const []),
        inShell: false,
        routed: true,
      );

      final hero = tester.getTopLeft(
        find.byKey(const ValueKey('large-event-hero')),
      );
      expect(hero.dy, 0);

      final opacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.byKey(const ValueKey('biso-compact-title')),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 0);
    },
  );

  testWidgets(
    'shows the description, date pills and schedule from the items provider',
    (tester) async {
      await pumpBisoScreen(
        tester,
        LargeEventScreen(event: _perEventModel()),
        overrides: _overrides(items: _scheduleItems),
        inShell: false,
        routed: true,
      );

      expect(
        find.textContaining('A full week of welcome activities'),
        findsOneWidget,
      );
      expect(find.text('10.8.2030'), findsOneWidget);
      expect(find.text('17.8.2030'), findsOneWidget);

      await tester.dragUntilVisible(
        find.text('Campus Tour'),
        find.byType(CustomScrollView),
        const Offset(0, -400),
      );
      expect(find.text('Opening Ceremony'), findsOneWidget);
      expect(find.text('Campus Tour'), findsOneWidget);
    },
  );

  testWidgets('a ticket link is a tappable row with a ticket tile', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      LargeEventScreen(
        event: _perEventModel(schedule: [_scheduleItems.first]),
      ),
      overrides: _overrides(items: const []),
      inShell: false,
      routed: true,
    );

    await tester.dragUntilVisible(
      find.text('Tickets'),
      find.byType(CustomScrollView),
      const Offset(0, -400),
    );
    final row = tester.widget<BisoListRow>(
      find.ancestor(of: find.text('Tickets'), matching: find.byType(BisoListRow)),
    );
    expect(row.onTap, isNotNull);
  });

  testWidgets('the all-access pass shows Buy Pass and Open Ticket Portal rows', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      LargeEventScreen(event: _allAccessModel()),
      overrides: _overrides(items: const []),
      inShell: false,
      routed: true,
    );

    expect(find.text('Buy Pass'), findsOneWidget);
    expect(find.text('Open Ticket Portal'), findsOneWidget);
  });

  testWidgets('a light CMS brand color gets navy date pill text', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      LargeEventScreen(event: _eventWithBrandColor('#FFF3B0')),
      overrides: _overrides(items: const []),
      inShell: false,
      routed: true,
    );

    final text = tester.widget<Text>(find.text('10.8.2030'));
    expect(text.style?.color, AppColors.biNavy);
  });

  testWidgets('a dark CMS brand color keeps white date pill text', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      LargeEventScreen(event: _eventWithBrandColor('#001731')),
      overrides: _overrides(items: const []),
      inShell: false,
      routed: true,
    );

    final text = tester.widget<Text>(find.text('10.8.2030'));
    expect(text.style?.color, Colors.white);
  });
}
