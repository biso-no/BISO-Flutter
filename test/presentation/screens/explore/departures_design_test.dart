import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/models/entur_models.dart';
import 'package:biso/data/services/entur_service.dart';
import 'package:biso/presentation/screens/explore/departures_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/ui/entur_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

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

final _stopPlaces = [
  StopPlaceModel(
    stopPlaceId: 'NSR:StopPlace:1',
    name: 'Test Stop',
    campusId: _campus.id,
  ),
];

/// Two fixed departures: one on schedule, one running 5 minutes late. Times
/// sit at whole-minute-plus-30-seconds offsets from "now" so that
/// `Duration.inMinutes` truncation stays stable against normal test-runner
/// scheduling jitter.
EnturDepartureBoard _board() {
  final now = DateTime.now();
  return EnturDepartureBoard(
    stopPlaceId: 'NSR:StopPlace:1',
    stopPlaceName: 'Test Stop',
    updatedAt: now,
    calls: [
      EnturEstimatedCall(
        realtime: true,
        aimedDepartureTime: now.add(const Duration(minutes: 10, seconds: 30)),
        expectedDepartureTime: now.add(
          const Duration(minutes: 10, seconds: 30),
        ),
        destination: 'On Time Destination',
        lineId: 'line-1',
        lineName: 'Line 1',
        transportMode: 'bus',
        quayId: 'quay-1',
      ),
      EnturEstimatedCall(
        realtime: true,
        aimedDepartureTime: now.add(const Duration(minutes: 15, seconds: 30)),
        expectedDepartureTime: now.add(
          const Duration(minutes: 20, seconds: 30),
        ),
        destination: 'Delayed Destination',
        lineId: 'line-2',
        lineName: 'Line 2',
        transportMode: 'metro',
        quayId: 'quay-2',
      ),
    ],
  );
}

/// Serves fixed stop places and a fixed departure board. Offline and
/// deterministic: `subscribeToDepartures` never opens a realtime channel, so
/// the board never changes underneath the test, mirroring the fakes in
/// jobs_design_test.dart.
class _FakeEnturService extends EnturService {
  _FakeEnturService(this.board);

  final EnturDepartureBoard board;

  @override
  Future<List<StopPlaceModel>> getStopPlacesForCampus(
    String campusId,
  ) async => _stopPlaces;

  @override
  Future<EnturDepartureBoard?> getDeparturesByStopPlaceId(
    String stopPlaceId,
  ) async => board;

  @override
  void subscribeToDepartures(String stopPlaceId) {
    // No realtime channel in tests: the board above is fixed.
  }
}

List<Override> _overrides(EnturDepartureBoard board) => [
  filterCampusProvider.overrideWithValue(_campus),
  enturServiceProvider.overrideWithValue(_FakeEnturService(board)),
];

void main() {
  testWidgets('Departures builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const DeparturesScreen(),
      routed: true,
      overrides: _overrides(_board()),
    );
  });

  testWidgets(
    'two fake departures render as rows, and the delayed one shows its '
    'value in palette.warning and its delay text',
    (tester) async {
      final board = _board();
      await pumpBisoScreen(
        tester,
        const DeparturesScreen(),
        routed: true,
        overrides: _overrides(board),
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('On Time Destination'), findsOneWidget);
      expect(find.text('Delayed Destination'), findsOneWidget);
      expect(find.text('10 min'), findsOneWidget);
      expect(find.text('20 min'), findsOneWidget);

      final palette = BisoPalette.of(tester.element(find.text('10 min')));
      final onTimeValue = tester.widget<Text>(find.text('10 min'));
      final delayedValue = tester.widget<Text>(find.text('20 min'));

      expect(
        onTimeValue.style?.color,
        palette.muted,
        reason: 'an on-time departure keeps the default muted value color',
      );
      expect(
        delayedValue.style?.color,
        palette.warning,
        reason: 'a realtime delay colors the value text palette.warning',
      );

      // Restored delay wording (verbatim from the pre-migration tile, see
      // git show 29d83f0:lib/.../departures_screen.dart): only the delayed
      // row shows it, appended to the subtitle.
      final aimedTimeText = DateFormat(
        'HH:mm',
      ).format(board.calls[1].aimedDepartureTime);
      expect(
        find.text('Line 2 · Delayed +5m · Scheduled $aimedTimeText'),
        findsOneWidget,
        reason:
            'the delayed row appends the old "Delayed +Xm" / scheduled '
            'time wording to its subtitle',
      );
      expect(
        find.text('Line 1'),
        findsOneWidget,
        reason:
            'the on-time row keeps a plain line-name subtitle, with no '
            'delay text appended',
      );
      expect(
        find.textContaining('Delayed +'),
        findsOneWidget,
        reason: 'the delay wording appears exactly once, only on the '
            'delayed row',
      );
    },
  );
}
