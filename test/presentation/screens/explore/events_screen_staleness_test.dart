import 'dart:async';

import 'package:biso/core/logging/app_logger.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/models/event_model.dart';
import 'package:biso/data/services/event_service.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/screens/explore/events_screen.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression cover for the staleness guard added to events_screen,
/// jobs_screen and marketplace_screen.
///
/// The guard drops a page whose campus/search no longer matches what the
/// user is looking at. It originally did that with a bare `return`, which
/// left `_isLoadingMore` latched forever: the flag is only ever reset on
/// the campus axis (`_ensureInitialLoad`), and the search axis reaches
/// `_fetchPage` through `_reload()`, whose `replace` branch never touches
/// it. A load-more dropped because the search changed therefore stranded
/// the trailing spinner and made `_onScroll` refuse to page again for the
/// life of the screen.
///
/// **Why events_screen and not the other two.** All three share the guard,
/// but only events exposes the two seams a test of this needs as *public*
/// providers: `eventServiceProvider` (so the service can be replaced with a
/// `Completer`-gated fake) and `eventsSearchTermProvider` (so the search
/// axis can be flipped mid-flight). jobs_screen's service provider is
/// private (`_jobServiceProvider`) and it has no search wiring at all;
/// marketplace_screen's is private too (`_webshopServiceProvider`) and its
/// search lives in a private `_search` field rather than a provider, so
/// neither can be driven from a test without first adding a DI seam to the
/// screen. One solid test on the screen that is genuinely testable beats
/// three that need new production seams to exist.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // AppLogger.info reads a `late final` Talker; every code path under
    // test logs, so the logger has to exist. Console output is off so the
    // test's own output stays readable.
    await AppLogger.initialize(enableConsole: false);
  });

  const campus = CampusModel(
    id: 'oslo',
    name: 'Oslo',
    description: 'Test campus',
    location: 'Oslo',
    imageUrl: '',
    heroImageUrl: '',
    stats: CampusStats(),
  );

  /// One page worth of events, so `_hasMore` stays true
  /// (`items.length >= _pageSize`, and `_pageSize` is 20).
  List<EventModel> page(String label) => List.generate(
    20,
    (i) => EventModel(
      id: '$label-$i',
      title: '$label $i',
      description: 'desc',
      startDate: DateTime.utc(2030, 1, 1),
      campusId: campus.id,
      // Deliberately no images: _EventCard would otherwise build an
      // Image.network, which cannot resolve under flutter_test.
    ),
  );

  testWidgets(
    'a load-more dropped because the search changed releases the paging '
    'latch: the trailing spinner disappears and paging still works',
    (tester) async {
      addTearDown(tester.view.reset);
      // Tall enough that 20 cards overflow it and the list is scrollable
      // (so _onScroll can reach its trigger zone), wide enough that
      // _EventCard's date/location Rows do not RenderFlex-overflow — a
      // pre-existing tightness on very narrow viewports, unrelated to
      // what is under test here.
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1.0;

      final service = _FakeEventService();
      final container = ProviderContainer(
        overrides: [
          eventServiceProvider.overrideWithValue(service),
          filterCampusProvider.overrideWithValue(campus),
          campusInitializedProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);

      // Page 1 lands immediately.
      service.enqueue(Future.value(page('Old')));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: EventsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Old 0'), findsOneWidget);
      expect(service.calls, hasLength(1));
      expect(renderedRowCount(tester), 20, reason: 'no trailing spinner yet');

      // --- trigger a load-more and hold its page in flight -------------
      final inFlight = Completer<List<EventModel>>();
      service.enqueue(inFlight.future);

      await tester.drag(find.byType(ListView), const Offset(0, -4000));
      await tester.pump();

      expect(
        service.calls,
        hasLength(2),
        reason: '_onScroll should have fired _loadMore',
      );
      expect(service.calls.last.search, isNull);
      expect(
        renderedRowCount(tester),
        21,
        reason: 'the trailing spinner row is present while page 2 is in '
            'flight',
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Scroll back to the top before the drop so the assertions below are
      // not perturbed by a scroll correction (removing the spinner row
      // shrinks maxScrollExtent, which at the very bottom would clamp the
      // offset, notify _onScroll and legitimately start another page).
      await tester.drag(find.byType(ListView), const Offset(0, 4000));
      await tester.pumpAndSettle();

      // --- the user searches while page 2 is still in flight -----------
      container.read(eventsSearchTermProvider.notifier).state = 'gala';

      // ...and only now does the old page come back.
      inFlight.complete(page('Stale'));
      await tester.pumpAndSettle();

      // The guard itself still works: the old search's page is not merged.
      expect(find.textContaining('Stale'), findsNothing);
      expect(
        container.read(eventsSearchTermProvider),
        'gala',
        reason: 'sanity: the search axis really did change mid-flight',
      );

      // THE REGRESSION. `renderedRowCount` is read off the ListView's
      // childrenDelegate rather than by hunting for a spinner widget, so it
      // is independent of where the list happens to be scrolled: a lazily
      // built trailing spinner that is merely off-screen would still be
      // counted here.
      expect(
        renderedRowCount(tester),
        20,
        reason: 'the dropped page must have released _isLoadingMore; '
            'otherwise the trailing spinner row outlives the request that '
            'raised it, for the life of the screen',
      );

      // ...and paging is not wedged: scrolling to the bottom again must
      // start a new page. Pre-fix, _onScroll bails on `_isLoadingMore`
      // and this call never happens.
      service.enqueue(Future.value(page('Gala')));
      await tester.drag(find.byType(ListView), const Offset(0, -4000));

      // No pumpAndSettle here on purpose. `_onScroll` -> `_loadMore` ->
      // `listEvents` all run synchronously while the drag's scroll
      // notification is dispatched, so the call is already recorded — and
      // a stranded spinner animates forever, which would turn the
      // regression into an opaque "pumpAndSettle timed out" instead of the
      // legible expectation failure below.
      expect(
        service.calls,
        hasLength(3),
        reason: 'paging must resume after a dropped page; pre-fix _onScroll '
            'bails on the still-latched _isLoadingMore and this page is '
            'never requested',
      );
      expect(service.calls.last.search, 'gala');

      // Let the page that was just requested land, so the test does not end
      // with work still queued behind it.
      await tester.pump();
      await tester.pump();
    },
  );
}

/// Number of `itemBuilder` rows the list is currently configured to build.
///
/// `ListView.separated` interleaves separators, so its delegate reports
/// `2 * items - 1`. Reading it back gives the screen's
/// `_events.length + (_isLoadingMore ? 1 : 0)` exactly, without depending
/// on which rows happen to be laid out.
int renderedRowCount(WidgetTester tester) {
  final list = tester.widget<ListView>(find.byType(ListView));
  final delegateCount = list.childrenDelegate.estimatedChildCount!;
  return (delegateCount + 1) ~/ 2;
}

class _Call {
  const _Call({required this.offset, required this.search});

  final int offset;
  final String? search;
}

/// Replaces the real Appwrite-backed service. Only [listEvents] is
/// reachable from the screen, and every response is handed in by the test
/// so a page can be held in flight for as long as it needs to be.
class _FakeEventService extends EventService {
  final List<_Call> calls = [];
  final List<Future<List<EventModel>>> _queued = [];

  void enqueue(Future<List<EventModel>> response) => _queued.add(response);

  @override
  Future<List<EventModel>> listEvents({
    String? campusId,
    String locale = 'no',
    int limit = 20,
    int offset = 0,
    bool includePast = false,
    String? search,
  }) {
    calls.add(_Call(offset: offset, search: search));
    if (_queued.isEmpty) {
      fail('unexpected listEvents call #${calls.length} (offset $offset, '
          'search $search)');
    }
    return _queued.removeAt(0);
  }
}
