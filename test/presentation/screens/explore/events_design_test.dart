import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/models/event_model.dart';
import 'package:biso/data/services/event_service.dart';
import 'package:biso/presentation/screens/explore/events_screen.dart';
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

void main() {
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
}
