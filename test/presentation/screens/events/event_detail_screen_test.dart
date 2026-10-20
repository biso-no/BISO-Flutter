import 'package:biso/core/theme/biso_page.dart';
import 'package:biso/data/models/event_model.dart';
import 'package:biso/presentation/screens/events/event_detail_screen.dart';
import 'package:biso/providers/event/event_segment_provider.dart';
import 'package:biso/providers/events/events_provider.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

EventModel _event() => EventModel(
  id: 'ev-1',
  slug: 'kickoff',
  title: 'Autumn kickoff',
  description: '<p>Meet the organisations.</p>',
  startDate: DateTime.utc(2030, 9, 3, 17),
  campusId: '1',
  contactName: 'Kari',
);

List<Override> _overrides(EventModel? event, {bool member = false}) => [
  eventDetailProvider.overrideWith((ref, idOrSlug) async => event),
  hasValidMembershipProvider.overrideWithValue(member),
  // Signed out: the trip card reads nothing from Appwrite.
  myTripProvider.overrideWith((ref, eventId) async => const []),
];

void main() {
  testWidgets('shows the title and the localized Description heading', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const EventDetailScreen(idOrSlug: 'kickoff'),
      overrides: _overrides(_event()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Autumn kickoff'), findsWidgets);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Organized by Kari'), findsOneWidget);
  });

  testWidgets('a missing event for a non-member says members only', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const EventDetailScreen(idOrSlug: 'secret'),
      overrides: _overrides(null),
    );
    await tester.pumpAndSettle();

    expect(find.text('Members only'), findsOneWidget);
    expect(find.text('Become a member'), findsOneWidget);
  });

  testWidgets('a missing event for a member says it is not available', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const EventDetailScreen(idOrSlug: 'gone'),
      overrides: _overrides(null, member: true),
    );
    await tester.pumpAndSettle();

    expect(find.text("This event isn't available"), findsOneWidget);
    expect(find.text('Become a member'), findsNothing);
  });

  testWidgets('builds on BisoPage', (tester) async {
    await pumpBisoScreen(
      tester,
      const EventDetailScreen(idOrSlug: 'kickoff'),
      overrides: _overrides(_event()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BisoPage), findsOneWidget);
  });
}
