import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/models/event_model.dart';
import 'package:biso/data/services/event_service.dart';
import 'package:biso/presentation/screens/explore/events_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/auth/auth_provider.dart';
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

/// One page worth of events, so `_hasMore` stays true for offset 0
/// (`items.length >= _pageSize`, and `_pageSize` is 20).
List<EventModel> _page(String label, int count) => List.generate(
  count,
  (i) => EventModel(
    id: '$label-$i',
    title: '$label $i',
    description: 'desc',
    startDate: DateTime.utc(2030, 1, 1),
    campusId: _campus.id,
    // Deliberately no images: _EventCard would otherwise build a
    // CachedNetworkImage, which cannot resolve under flutter_test.
  ),
);

/// Replaces the real Appwrite-backed service. Deterministic and offline:
/// page one (offset 0) and page two (offset 20) each return a full page,
/// every later offset returns nothing so `_hasMore` settles to false.
/// Mirrors the fakes in events_screen_staleness_test.dart, but with no
/// Completer to hold in flight — every call resolves immediately, so the
/// test ends with no pending timers or futures.
class _FakeEventService extends EventService {
  final List<int> offsets = [];

  @override
  Future<List<EventModel>> listEvents({
    String? campusId,
    String locale = 'no',
    int limit = 20,
    int offset = 0,
    bool includePast = false,
    String? search,
  }) async {
    offsets.add(offset);
    if (offset >= 40) return const [];
    return _page('p$offset', 20);
  }
}

List<Override> _overrides(_FakeEventService service) => [
  eventServiceProvider.overrideWithValue(service),
  filterCampusProvider.overrideWithValue(_campus),
  campusInitializedProvider.overrideWithValue(true),
];

/// Serves one fixed list of events, regardless of paging. Offline and
/// deterministic, mirroring `_FakeEventService` above.
class _FixedEventService extends EventService {
  _FixedEventService(this._events);

  final List<EventModel> _events;

  @override
  Future<List<EventModel>> listEvents({
    String? campusId,
    String locale = 'no',
    int limit = 20,
    int offset = 0,
    bool includePast = false,
    String? search,
  }) async {
    if (offset > 0) return const [];
    return _events;
  }
}

/// Signed out, so the detail sheet's personalised trip card renders nothing
/// and nothing reaches Appwrite. Membership is overridden separately.
class _SignedOut extends StateNotifier<AuthState> implements AuthNotifier {
  _SignedOut() : super(const AuthState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

EventModel _ticketed({required bool memberOnly}) => EventModel(
  id: 'gala',
  title: 'Winter Gala',
  description: 'desc',
  startDate: DateTime.now().add(const Duration(days: 10)),
  campusId: _campus.id,
  price: 400,
  memberPrice: 250,
  pricingMode: 'paid',
  memberOnly: memberOnly,
  ticketUrl: 'https://tickets.example/gala',
);

Future<void> _openGala(
  WidgetTester tester, {
  required bool memberOnly,
  required bool isMember,
}) async {
  await pumpBisoScreen(
    tester,
    const EventsScreen(),
    routed: true,
    overrides: [
      eventServiceProvider.overrideWithValue(
        _FixedEventService([_ticketed(memberOnly: memberOnly)]),
      ),
      filterCampusProvider.overrideWithValue(_campus),
      campusInitializedProvider.overrideWithValue(true),
      authStateProvider.overrideWith((_) => _SignedOut()),
      hasValidMembershipProvider.overrideWithValue(isMember),
    ],
  );
}

ButtonStyleButton _buttonLabelled(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );

void main() {
  group('members-only events', () {
    testWidgets('the card marks the event and shows the member price', (
      tester,
    ) async {
      await _openGala(tester, memberOnly: true, isMember: false);

      expect(find.byType(BisoMembersBadge), findsOneWidget);
      expect(find.textContaining('Members NOK 250'), findsOneWidget);
    });

    testWidgets('an open event carries no members badge', (tester) async {
      await _openGala(tester, memberOnly: false, isMember: false);
      expect(find.byType(BisoMembersBadge), findsNothing);
    });

    testWidgets('a non-member cannot reach the tickets', (tester) async {
      await _openGala(tester, memberOnly: true, isMember: false);
      await tester.tap(find.text('Winter Gala'));
      await tester.pumpAndSettle();

      expect(_buttonLabelled(tester, 'Members only').onPressed, isNull);
      expect(find.text('Get tickets'), findsNothing);
    });

    testWidgets('a member gets the ticket button', (tester) async {
      await _openGala(tester, memberOnly: true, isMember: true);
      await tester.tap(find.text('Winter Gala'));
      await tester.pumpAndSettle();

      expect(_buttonLabelled(tester, 'Get tickets').onPressed, isNotNull);
    });

    testWidgets('anyone gets the ticket button for an open event', (
      tester,
    ) async {
      await _openGala(tester, memberOnly: false, isMember: false);
      await tester.tap(find.text('Winter Gala'));
      await tester.pumpAndSettle();

      expect(_buttonLabelled(tester, 'Get tickets').onPressed, isNotNull);
    });
  });

  testWidgets('Events builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const EventsScreen(),
      routed: true,
      overrides: _overrides(_FakeEventService()),
    );
  });

  testWidgets('scrolling to the bottom of the list loads the next page', (
    tester,
  ) async {
    final service = _FakeEventService();
    await pumpBisoScreen(
      tester,
      const EventsScreen(),
      routed: true,
      overrides: _overrides(service),
    );

    expect(find.text('p0 0'), findsOneWidget);
    expect(service.offsets, [0], reason: 'only page one is fetched at rest');

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -6000));
    await tester.pumpAndSettle();

    expect(
      service.offsets,
      [0, 20],
      reason: 'scrolling to the bottom must request the next page',
    );
    expect(find.text('p20 0'), findsOneWidget);
  });

  testWidgets(
    'a completed event shows a muted status chip and an upcoming one shows '
    'the link color',
    (tester) async {
      final now = DateTime.now();
      final events = [
        EventModel(
          id: 'ended',
          title: 'Ended Event',
          description: 'desc',
          // No endDate, so lifecycle is derived from startDate alone: a
          // start in the past makes `isCompleted` true immediately.
          startDate: now.subtract(const Duration(days: 2)),
          campusId: _campus.id,
        ),
        EventModel(
          id: 'upcoming',
          title: 'Upcoming Event',
          description: 'desc',
          startDate: now.add(const Duration(days: 2)),
          campusId: _campus.id,
        ),
      ];

      await pumpBisoScreen(
        tester,
        const EventsScreen(),
        routed: true,
        overrides: [
          eventServiceProvider.overrideWithValue(_FixedEventService(events)),
          filterCampusProvider.overrideWithValue(_campus),
          campusInitializedProvider.overrideWithValue(true),
        ],
      );

      final endedChipText = tester.widget<Text>(find.text('Ended'));
      final upcomingChipText = tester.widget<Text>(find.text('Upcoming'));

      expect(
        endedChipText.style?.color,
        BisoPalette.light.muted,
        reason: 'a completed event is past/inactive, not the active/'
            'selected meaning `link` carries',
      );
      expect(upcomingChipText.style?.color, BisoPalette.light.link);
    },
  );

  testWidgets(
    'shortening a search below two characters clears the filter instead of '
    'keeping the old query',
    (tester) async {
      final service = _SearchRecordingEventService();
      await pumpBisoScreen(
        tester,
        const EventsScreen(),
        routed: true,
        overrides: [
          eventServiceProvider.overrideWithValue(service),
          filterCampusProvider.overrideWithValue(_campus),
          campusInitializedProvider.overrideWithValue(true),
        ],
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(EventsScreen)),
      );

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      final field = find.byType(TextField);

      await tester.enterText(field, 'ga');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(container.read(eventsSearchTermProvider), 'ga');
      expect(service.searches.last, 'ga');

      await tester.enterText(field, 'g');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(
        container.read(eventsSearchTermProvider),
        isNull,
        reason: 'a one-character query is below the API minimum, so the list '
            'must stop filtering by the previous query',
      );
      expect(service.searches.last, isNull);
    },
  );
}

/// Records the search term of every request; always returns one short page.
class _SearchRecordingEventService extends EventService {
  final List<String?> searches = [];

  @override
  Future<List<EventModel>> listEvents({
    String? campusId,
    String locale = 'no',
    int limit = 20,
    int offset = 0,
    bool includePast = false,
    String? search,
  }) async {
    searches.add(search);
    return _page('s', 2);
  }
}
