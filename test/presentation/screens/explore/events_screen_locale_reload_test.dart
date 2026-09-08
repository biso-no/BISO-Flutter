import 'dart:async';

import 'package:biso/core/logging/app_logger.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/models/event_model.dart';
import 'package:biso/data/services/event_service.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/screens/explore/events_screen.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/ui/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression cover for "events don't react to a language change".
///
/// `EventsScreen` used to read the locale once via `ref.read` inside
/// `_fetchPage`, and keyed `_ensureInitialLoad` only by campus. So when the
/// saved locale finished loading asynchronously, or the user switched
/// language while the screen was mounted, the already-loaded titles stayed
/// in the previous language, and scrolling further fetched later pages in
/// the *new* locale — mixing languages in one list.
///
/// The fix: `build()` now watches `localeProvider` and feeds it into
/// `_ensureInitialLoad` alongside campus, so a locale change replaces page
/// one; and the staleness guard in `_fetchPage` now also compares locale,
/// so a page fetched for the old locale is dropped instead of merged.
///
/// This test drives both halves at once, mirroring
/// events_screen_staleness_test.dart's shape (a `Completer`-gated fake
/// service so a page can be held in flight) but swapping the axis that
/// changes mid-flight from search to locale — the interaction the review
/// specifically called out: adding a locale comparison to the guard
/// without making the screen reactive to locale would strand the load-more
/// spinner with no replacement fetch ever queued.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
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

  /// One page worth of events tagged with the locale they were "fetched
  /// for", so rendered text reveals which language's page is on screen —
  /// mirrors events_screen_staleness_test.dart's `page(label)` helper.
  List<EventModel> page(String locale) => List.generate(
    20,
    (i) => EventModel(
      id: '$locale-$i',
      title: '$locale-title-$i',
      description: 'desc',
      startDate: DateTime.utc(2030, 1, 1),
      campusId: campus.id,
      // Deliberately no images: _EventCard would otherwise build an
      // Image.network, which cannot resolve under flutter_test.
    ),
  );

  testWidgets(
    'switching locale mid-load-more replaces page one in the new language '
    'and releases the paging latch, instead of stranding the spinner or '
    'mixing languages',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1.0;

      final service = _FakeEventService();
      final container = ProviderContainer(
        overrides: [
          eventServiceProvider.overrideWithValue(service),
          filterCampusProvider.overrideWithValue(campus),
          campusInitializedProvider.overrideWithValue(true),
          localeProvider.overrideWith((ref) => _TestLocaleNotifier()),
        ],
      );
      addTearDown(container.dispose);

      // Page 1 for the starting locale ('en', LocaleNotifier's default)
      // lands immediately.
      service.enqueue(Future.value(page('en')));

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

      expect(find.text('en-title-0'), findsOneWidget);
      expect(service.calls, hasLength(1));
      expect(service.calls.single.locale, 'en');
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
      expect(service.calls.last.locale, 'en');
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

      // --- the user switches language while page 2 is still in flight --
      final localeNotifier =
          container.read(localeProvider.notifier) as _TestLocaleNotifier;
      // The reactive rebuild this triggers calls _ensureInitialLoad with
      // the new locale, which resets paging state and immediately starts a
      // replacement page-1 fetch — enqueue it before the state change lands
      // so that fetch has a response waiting.
      service.enqueue(Future.value(page('no')));
      localeNotifier.setForTest('no');
      await tester.pump();

      // ...and only now does the old (English) page 2 come back.
      inFlight.complete(page('en'));
      await tester.pumpAndSettle();

      // The guard itself works: the stale English load-more page is not
      // merged into the list.
      expect(find.textContaining('en-title-2'), findsNothing);

      // THE REGRESSION (reactivity half). A locale change must actually
      // replace page one — not just get compared away by the guard with no
      // replacement queued. The list must show the NEW locale's content,
      // not be left empty or stuck on the old language.
      expect(find.text('no-title-0'), findsOneWidget);
      expect(find.textContaining('en-title'), findsNothing);

      // THE REGRESSION (guard half). `renderedRowCount` is read off the
      // ListView's childrenDelegate rather than by hunting for a spinner
      // widget, so it is independent of where the list happens to be
      // scrolled: a lazily built trailing spinner that is merely off-screen
      // would still be counted here.
      expect(
        renderedRowCount(tester),
        20,
        reason: 'the dropped stale-locale page must have released '
            '_isLoadingMore; otherwise the trailing spinner row outlives '
            'the request that raised it, for the life of the screen',
      );

      // ...and paging is not wedged: scrolling to the bottom again must
      // start a new page, for the new locale.
      service.enqueue(Future.value(page('no')));
      await tester.drag(find.byType(ListView), const Offset(0, -4000));

      // No pumpAndSettle here on purpose, matching
      // events_screen_staleness_test.dart: _onScroll -> _loadMore ->
      // listEvents all run synchronously while the drag's scroll
      // notification is dispatched, so the call is already recorded — and
      // a stranded spinner animates forever, which would turn the
      // regression into an opaque "pumpAndSettle timed out" instead of the
      // legible expectation failure below.
      expect(
        service.calls.last.locale,
        'no',
        reason: 'paging must resume, for the new locale, after a dropped '
            'page; pre-fix _onScroll bails on the still-latched '
            '_isLoadingMore and this page is never requested',
      );

      // Let the page that was just requested land, so the test does not
      // end with work still queued behind it.
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
  const _Call({required this.offset, required this.locale});

  final int offset;
  final String locale;
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
    calls.add(_Call(offset: offset, locale: locale));
    if (_queued.isEmpty) {
      fail(
        'unexpected listEvents call #${calls.length} (offset $offset, '
        'locale $locale)',
      );
    }
    return _queued.removeAt(0);
  }
}

/// A [LocaleNotifier] the test can flip synchronously and deterministically.
///
/// The real notifier's `setLocale()` round-trips through
/// `SharedPreferences.getInstance()` before ever assigning `state`, and in
/// `flutter_test` — without `SharedPreferences.setMockInitialValues()` —
/// that call throws (no platform channel handler is registered), so the
/// catch block swallows it and `state` is never reached. [setForTest]
/// assigns `state` directly, sidestepping persistence entirely: this test
/// is about the *screen's* reactivity to a locale change, not about how the
/// locale is persisted.
class _TestLocaleNotifier extends LocaleNotifier {
  void setForTest(String languageCode) {
    state = Locale(languageCode);
  }
}
