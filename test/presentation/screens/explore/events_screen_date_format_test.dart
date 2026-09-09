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
import 'package:intl/intl.dart';

/// Regression cover for "events display 2 hours early".
///
/// Appwrite returns event timestamps with an explicit UTC offset (e.g.
/// "2026-09-22T10:00:00.000+00:00" — the real Karrieredagene payload used
/// below, also covered in event_model_appwrite_test.dart). `DateTime.parse`
/// preserves that as a DateTime with `isUtc == true`. `DateFormat` renders a
/// DateTime's own fields and never consults `isUtc` to decide whether to
/// convert first, so formatting the parsed value directly prints the *UTC*
/// wall-clock time — e.g. "10:00" for an event that actually starts at
/// 12:00 in Oslo (UTC+2 in September, CEST).
///
/// `_EventCard` fixes this with a `.toLocal()` call before formatting. This
/// file proves the difference that call makes, then pins the actual
/// rendered widget text so a future edit that "simplifies away" the
/// `.toLocal()` call is caught immediately instead of silently
/// reintroducing the bug.
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

  // The real Karrieredagene payload from the bug report: Appwrite's
  // start_date carries an explicit "+00:00" offset.
  final startDate = DateTime.parse('2026-09-22T10:00:00.000+00:00');

  test('DateTime.parse marks an Appwrite UTC-offset timestamp isUtc', () {
    // Sanity check for the premise of the whole bug: if this ever becomes
    // false (e.g. Appwrite changes its serialization), the .toLocal() fix
    // below stops being necessary.
    expect(startDate.isUtc, isTrue);
  });

  test(
    'formatting the raw parsed DateTime always prints the UTC wall clock, '
    'independent of the host machine\'s own time zone',
    () {
      // No .toLocal() involved, so this holds on every dev machine and CI
      // runner regardless of its own local time zone.
      expect(DateFormat('MMM dd, HH:mm').format(startDate), 'Sep 22, 10:00');
    },
  );

  test(
    'formatting startDate.toLocal() prints the device wall-clock time, '
    'which differs from the raw UTC formatting whenever the host itself is '
    'not on UTC',
    () {
      final hostOffset = startDate.toLocal().timeZoneOffset;
      final rawFormatted = DateFormat('MMM dd, HH:mm').format(startDate);
      final localFormatted = DateFormat(
        'MMM dd, HH:mm',
      ).format(startDate.toLocal());

      if (hostOffset == Duration.zero) {
        // The bug is invisible on a UTC-local machine (e.g. this repo's own
        // CI, a default GitHub Actions ubuntu-latest runner) because
        // toLocal() is a no-op there — document that rather than asserting
        // a difference that cannot exist in this environment.
        expect(localFormatted, rawFormatted);
      } else {
        expect(
          localFormatted,
          isNot(equals(rawFormatted)),
          reason:
              'a UTC-offset input must format to the local wall clock, not '
              'the UTC one, whenever the device has a non-zero UTC offset',
        );
      }

      // Pin the exact reproduction from the bug report: Oslo is UTC+2 in
      // September (CEST). This assertion only runs when the test happens to
      // execute on a +2 host (e.g. a Norway-based dev machine); it is a
      // no-op everywhere else, same as the branch above already covers a
      // UTC runner correctly.
      if (hostOffset == const Duration(hours: 2)) {
        expect(localFormatted, 'Sep 22, 12:00');
      }
    },
  );

  testWidgets(
    'EventsScreen renders the event start time converted to the device '
    'local time, not the raw UTC value parsed from Appwrite',
    (tester) async {
      addTearDown(tester.view.reset);
      // Tall/wide enough that the single card lays out without overflow —
      // same sizing rationale as events_screen_staleness_test.dart.
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1.0;

      final event = EventModel(
        id: 'evt_kd',
        title: 'Karrieredagene',
        description: 'desc',
        startDate: startDate,
        campusId: campus.id,
        // Deliberately no images: _EventCard would otherwise build an
        // Image.network, which cannot resolve under flutter_test.
      );

      final service = _FakeEventService([event]);
      final container = ProviderContainer(
        overrides: [
          eventServiceProvider.overrideWithValue(service),
          filterCampusProvider.overrideWithValue(campus),
          campusInitializedProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);

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

      final expectedText = DateFormat(
        'MMM dd, HH:mm',
      ).format(event.startDate.toLocal());
      expect(find.text(expectedText), findsOneWidget);

      // The regression this guards against: pre-fix, the card formatted
      // event.startDate directly (no .toLocal()), which prints the UTC
      // wall-clock time. That is only distinguishable from the fixed
      // behaviour on a host whose local offset for this instant is
      // non-zero — skip the negative assertion on a UTC host, where the two
      // strings are identical by construction (see the unit test above).
      if (event.startDate.toLocal().timeZoneOffset != Duration.zero) {
        expect(
          find.text(DateFormat('MMM dd, HH:mm').format(event.startDate)),
          findsNothing,
        );
      }
    },
  );
}

/// Minimal fake: returns the fixed event list for page one, and nothing for
/// any further page so the screen's `_hasMore` flips false immediately.
class _FakeEventService extends EventService {
  _FakeEventService(this._events);

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
