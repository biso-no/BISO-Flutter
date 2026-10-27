import 'dart:async';

import 'package:biso/data/models/event_model.dart';
import 'package:biso/data/models/event_rsvp.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/auth_service.dart';
import 'package:biso/data/services/event_rsvp_api_client.dart';
import 'package:biso/presentation/widgets/event/event_rsvp_card.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/events/event_rsvp_provider.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/biso_screen_harness.dart';

class _NeverAuthService extends AuthService {
  @override
  Future<UserModel?> getCurrentUser() => Completer<UserModel?>().future;
}

class _FakeAuth extends AuthNotifier {
  _FakeAuth({required bool signedIn}) : super(_NeverAuthService()) {
    if (signedIn) {
      state = AuthState(
        user: UserModel(id: 'student-a', name: 'A', email: 'a@bi.no'),
        isAuthenticated: true,
      );
    }
  }
}

class _FakeApi implements EventRsvpApi {
  _FakeApi({
    this.summary = const EventRsvpSummary(
      going: 4,
      maybe: 0,
      mine: null,
      open: true,
    ),
    this.fetchError,
    this.respondResult,
    this.respondError,
  });

  final EventRsvpSummary summary;
  final EventRsvpApiException? fetchError;
  final EventRsvpSummary? respondResult;
  final EventRsvpApiException? respondError;
  final List<EventRsvpStatus?> responses = [];

  @override
  Future<EventRsvpSummary> fetch(
    String eventId, {
    required bool signedIn,
  }) async {
    if (fetchError != null) throw fetchError!;
    return summary;
  }

  @override
  Future<EventRsvpSummary> respond(
    String eventId,
    EventRsvpStatus? status,
  ) async {
    responses.add(status);
    if (respondError != null) throw respondError!;
    return respondResult ?? summary;
  }
}

EventModel _event({bool memberOnly = false, DateTime? start, String? ticket}) =>
    EventModel(
      id: 'ev-1',
      title: 'Autumn kickoff',
      description: '',
      startDate: start ?? DateTime.utc(2030, 9, 3, 17),
      campusId: '1',
      memberOnly: memberOnly,
      ticketUrl: ticket,
    );

Future<void> _pump(
  WidgetTester tester,
  EventModel event,
  _FakeApi api, {
  bool signedIn = true,
  bool member = true,
}) async {
  await pumpBisoScreen(
    tester,
    Scaffold(
      body: SingleChildScrollView(child: EventRsvpCard(event: event)),
    ),
    inShell: false,
    routed: true,
    extraRoutes: [
      GoRoute(
        path: '/auth/login',
        builder: (_, _) => const Scaffold(body: Text('login page')),
      ),
    ],
    overrides: [
      eventRsvpApiProvider.overrideWithValue(api),
      authStateProvider.overrideWith((_) => _FakeAuth(signedIn: signedIn)),
      hasValidMembershipProvider.overrideWithValue(member),
    ],
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("shows three answers with the student's own selected", (
    tester,
  ) async {
    final api = _FakeApi(
      summary: const EventRsvpSummary(
        going: 4,
        maybe: 2,
        mine: EventRsvpStatus.maybe,
        open: true,
      ),
    );
    await _pump(tester, _event(), api);

    expect(find.text('Are you going?'), findsOneWidget);
    expect(find.text('Going'), findsOneWidget);
    expect(find.text('Maybe'), findsOneWidget);
    expect(find.text('Not going'), findsOneWidget);
    final button = tester.widget<SegmentedButton<EventRsvpStatus>>(
      find.byType(SegmentedButton<EventRsvpStatus>),
    );
    expect(button.selected, {EventRsvpStatus.maybe});
    expect(find.text('4 going · 2 maybe'), findsOneWidget);
  });

  testWidgets('tapping Going saves it and updates the count', (tester) async {
    final api = _FakeApi(
      respondResult: const EventRsvpSummary(
        going: 5,
        maybe: 0,
        mine: EventRsvpStatus.going,
        open: true,
      ),
    );
    await _pump(tester, _event(), api);
    expect(find.text('4 going'), findsOneWidget);

    await tester.tap(find.text('Going'));
    await tester.pumpAndSettle();

    expect(api.responses, [EventRsvpStatus.going]);
    expect(find.text('5 going'), findsOneWidget);
  });

  testWidgets('signed out shows sign-in and no answers', (tester) async {
    await _pump(tester, _event(), _FakeApi(), signedIn: false);

    expect(find.text('Sign in to respond'), findsOneWidget);
    expect(find.byType(SegmentedButton<EventRsvpStatus>), findsNothing);
    expect(find.text('4 going'), findsOneWidget);

    await tester.tap(find.text('Sign in to respond'));
    await tester.pumpAndSettle();
    expect(find.text('login page'), findsOneWidget);
  });

  testWidgets('members-only non-member sees counts only', (tester) async {
    await _pump(tester, _event(memberOnly: true), _FakeApi(), member: false);

    expect(find.text('4 going'), findsOneWidget);
    expect(find.byType(SegmentedButton<EventRsvpStatus>), findsNothing);
    expect(find.text('Sign in to respond'), findsNothing);
  });

  testWidgets('renders nothing for a completed event', (tester) async {
    await _pump(
      tester,
      _event(start: DateTime.utc(2020, 1, 1, 17)),
      _FakeApi(),
    );

    expect(find.text('Are you going?'), findsNothing);
    expect(find.byType(SegmentedButton<EventRsvpStatus>), findsNothing);
  });

  testWidgets('renders nothing when the API is not deployed', (tester) async {
    await _pump(
      tester,
      _event(),
      _FakeApi(
        fetchError: const EventRsvpApiException(
          EventRsvpApiErrorKind.notDeployed,
        ),
      ),
    );

    expect(find.text('Are you going?'), findsNothing);
  });

  testWidgets('shows a snackbar when saving fails', (tester) async {
    final api = _FakeApi(
      respondError: const EventRsvpApiException(EventRsvpApiErrorKind.network),
    );
    await _pump(tester, _event(), api);

    await tester.tap(find.text('Going'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't save your answer. Try again."), findsOneWidget);
    expect(find.text('4 going'), findsOneWidget);
  });

  testWidgets('says tickets are separate when the event sells them', (
    tester,
  ) async {
    await _pump(
      tester,
      _event(ticket: 'https://tickets.example/x'),
      _FakeApi(),
    );

    expect(
      find.text("Saying you're going doesn't get you a ticket."),
      findsOneWidget,
    );
  });

  testWidgets('shows no count line when nobody has answered', (tester) async {
    await _pump(
      tester,
      _event(),
      _FakeApi(
        summary: const EventRsvpSummary(
          going: 0,
          maybe: 0,
          mine: null,
          open: true,
        ),
      ),
    );

    expect(find.text('Are you going?'), findsOneWidget);
    expect(find.text('0 going'), findsNothing);
    expect(find.textContaining('·'), findsNothing);
  });
}
