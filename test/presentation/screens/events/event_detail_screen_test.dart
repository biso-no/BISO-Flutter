import 'dart:async';

import 'package:biso/core/theme/biso_page.dart';
import 'package:biso/data/models/event_model.dart';
import 'package:biso/data/models/event_rsvp.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/auth_service.dart';
import 'package:biso/data/services/event_rsvp_api_client.dart';
import 'package:biso/presentation/screens/events/event_detail_screen.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/event/event_segment_provider.dart';
import 'package:biso/providers/events/event_rsvp_provider.dart';
import 'package:biso/providers/events/events_provider.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

/// A signed-out session that never asks Appwrite who is signed in.
class _SignedOutAuth extends AuthNotifier {
  _SignedOutAuth() : super(_NeverAuthService()) {
    // The base constructor starts a check that never ends; settle it.
    state = const AuthState();
  }
}

class _NeverAuthService extends AuthService {
  @override
  Future<UserModel?> getCurrentUser() => Completer<UserModel?>().future;
}

/// Never reaches the network: the RSVP route reads as not deployed, so the
/// card stays hidden.
class _NoRsvpApi implements EventRsvpApi {
  @override
  Future<EventRsvpSummary> fetch(String eventId, {required bool signedIn}) =>
      throw const EventRsvpApiException(EventRsvpApiErrorKind.notDeployed);

  @override
  Future<EventRsvpSummary> respond(String eventId, EventRsvpStatus? status) =>
      throw const EventRsvpApiException(EventRsvpApiErrorKind.notDeployed);
}

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
  eventRsvpApiProvider.overrideWithValue(_NoRsvpApi()),
  authStateProvider.overrideWith((_) => _SignedOutAuth()),
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

  // Members-only events are readable by everyone (they show a members badge
  // and a locked ticket button), so a missing one is unpublished, deleted or
  // a bad link - for a non-member too. Offering membership would be a false
  // upsell.
  for (final member in [false, true]) {
    testWidgets(
      'a missing event says it is not available, '
      '${member ? 'for a member' : 'and offers no membership to a non-member'}',
      (tester) async {
        await pumpBisoScreen(
          tester,
          const EventDetailScreen(idOrSlug: 'gone'),
          overrides: _overrides(null, member: member),
        );
        await tester.pumpAndSettle();

        expect(find.text("This event isn't available"), findsOneWidget);
        expect(find.text('Members only'), findsNothing);
        expect(find.text('Become a member'), findsNothing);
      },
    );
  }

  testWidgets('a cancelled event opens and shows its Cancelled chip', (
    tester,
  ) async {
    final cancelled = EventModel(
      id: 'ev-3',
      title: 'Cancelled quiz',
      description: '<p>Quiz.</p>',
      startDate: DateTime.utc(2030, 9, 3, 17),
      campusId: '1',
      status: 'cancelled',
    );
    await pumpBisoScreen(
      tester,
      const EventDetailScreen(idOrSlug: 'ev-3'),
      overrides: _overrides(cancelled),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cancelled quiz'), findsWidgets);
    expect(find.text('Cancelled'), findsOneWidget);
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

  testWidgets('speaks Norwegian under the no locale', (tester) async {
    final event = EventModel(
      id: 'ev-2',
      title: 'Galla',
      description: '<p>Fest.</p>',
      startDate: DateTime.utc(2030, 9, 3, 17),
      campusId: '1',
      contactName: 'Kari',
      memberOnly: true,
      price: 400,
      memberPrice: 250,
      ticketUrl: 'https://tickets.example/gala',
    );
    await pumpBisoScreen(
      tester,
      const EventDetailScreen(idOrSlug: 'galla'),
      locale: const Locale('no'),
      overrides: _overrides(event),
    );
    await tester.pumpAndSettle();

    expect(find.text('Beskrivelse'), findsOneWidget);
    expect(find.text('Arrangert av Kari'), findsOneWidget);
    expect(find.text('Kun for medlemmer'), findsWidgets);
    expect(find.textContaining('Medlemmer NOK 250'), findsOneWidget);
    expect(
      find.textContaining('Dette arrangementet er for BISO'),
      findsOneWidget,
    );
  });
}
