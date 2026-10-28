import 'dart:async';

import 'package:biso/data/models/event_model.dart';
import 'package:biso/data/models/event_rsvp.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/auth_service.dart';
import 'package:biso/core/theme/biso_colors.dart';
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
  _FakeAuth({required bool signedIn, bool loading = false})
    : super(_NeverAuthService()) {
    // The base constructor starts a check that never ends; settle it.
    state = loading ? const AuthState(isLoading: true) : const AuthState();
    if (signedIn) signIn();
  }

  void signIn() {
    state = AuthState(
      user: UserModel(id: 'student-a', name: 'A', email: 'a@bi.no'),
      isAuthenticated: true,
    );
  }

  void finishLoading() => state = const AuthState();
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
  final List<bool> fetches = [];
  Completer<void>? holdRespond;

  @override
  Future<EventRsvpSummary> fetch(
    String eventId, {
    required bool signedIn,
  }) async {
    fetches.add(signedIn);
    if (fetchError != null) throw fetchError!;
    return summary;
  }

  @override
  Future<EventRsvpSummary> respond(
    String eventId,
    EventRsvpStatus? status,
  ) async {
    responses.add(status);
    await holdRespond?.future;
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

Finder _answer(EventRsvpStatus status) =>
    find.byKey(ValueKey('event-rsvp-${status.name}'));

// `FilledButton.icon` is a subclass, so match by `is`, not by exact type.
Finder _filled(EventRsvpStatus status) => find.descendant(
  of: _answer(status),
  matching: find.byWidgetPredicate((widget) => widget is FilledButton),
);

Future<void> _pump(
  WidgetTester tester,
  EventModel event,
  _FakeApi api, {
  bool signedIn = true,
  bool member = true,
  _FakeAuth? auth,
  double textScale = 1,
  Size size = const Size(390, 844),
}) async {
  await pumpBisoScreen(
    tester,
    Scaffold(
      body: SingleChildScrollView(child: EventRsvpCard(event: event)),
    ),
    inShell: false,
    routed: true,
    textScale: textScale,
    size: size,
    extraRoutes: [
      GoRoute(
        path: '/auth/login',
        builder: (_, _) => const Scaffold(body: Text('login page')),
      ),
    ],
    overrides: [
      eventRsvpApiProvider.overrideWithValue(api),
      authStateProvider.overrideWith(
        (_) => auth ?? _FakeAuth(signedIn: signedIn),
      ),
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
    expect(_filled(EventRsvpStatus.maybe), findsOneWidget);
    expect(_filled(EventRsvpStatus.going), findsNothing);
    expect(_filled(EventRsvpStatus.notGoing), findsNothing);
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
    expect(_answer(EventRsvpStatus.going), findsNothing);
    expect(find.text('4 going'), findsOneWidget);

    await tester.tap(find.text('Sign in to respond'));
    await tester.pumpAndSettle();
    expect(find.text('login page'), findsOneWidget);
  });

  testWidgets('members-only non-member sees counts only', (tester) async {
    await _pump(tester, _event(memberOnly: true), _FakeApi(), member: false);

    expect(find.text('4 going'), findsOneWidget);
    expect(_answer(EventRsvpStatus.going), findsNothing);
    expect(find.text('Sign in to respond'), findsNothing);
  });

  testWidgets('renders nothing for a completed event', (tester) async {
    await _pump(
      tester,
      _event(start: DateTime.utc(2020, 1, 1, 17)),
      _FakeApi(),
    );

    expect(find.text('Are you going?'), findsNothing);
    expect(_answer(EventRsvpStatus.going), findsNothing);
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

  testWidgets('the chosen answer stays lit while it is saving', (tester) async {
    final api = _FakeApi()..holdRespond = Completer<void>();
    await _pump(tester, _event(), api);

    await tester.tap(find.text('Going'));
    await tester.pump();

    final lit = tester.widget<ButtonStyleButton>(
      _filled(EventRsvpStatus.going),
    );
    expect(lit.onPressed, isNotNull);

    api.holdRespond!.complete();
    await tester.pumpAndSettle();
    expect(api.responses, [EventRsvpStatus.going]);
  });

  testWidgets('tapping the selected answer clears it', (tester) async {
    final api = _FakeApi(
      summary: const EventRsvpSummary(
        going: 4,
        maybe: 0,
        mine: EventRsvpStatus.going,
        open: true,
      ),
    );
    await _pump(tester, _event(), api);

    await tester.tap(find.text('Going'));
    await tester.pumpAndSettle();

    expect(api.responses, [null]);
  });

  testWidgets('a signed-in student who signs in later gets the buttons', (
    tester,
  ) async {
    final auth = _FakeAuth(signedIn: false);
    final api = _FakeApi();
    await _pump(tester, _event(), api, auth: auth);
    expect(api.fetches, [false]);
    expect(_answer(EventRsvpStatus.going), findsNothing);

    auth.signIn();
    await tester.pumpAndSettle();

    expect(api.fetches, [false, true]);
    expect(_answer(EventRsvpStatus.going), findsOneWidget);
  });

  testWidgets('renders nothing and fetches nothing while auth loads', (
    tester,
  ) async {
    final auth = _FakeAuth(signedIn: false, loading: true);
    final api = _FakeApi();
    await _pump(tester, _event(), api, auth: auth);
    expect(find.text('Sign in to respond'), findsNothing);
    expect(find.text('Are you going?'), findsNothing);
    expect(api.fetches, isEmpty);

    auth.signIn();
    await tester.pumpAndSettle();
    expect(api.fetches, [true]);
    expect(_answer(EventRsvpStatus.going), findsOneWidget);
  });

  testWidgets('answers are outlined in the primary colour, not left faint', (
    tester,
  ) async {
    // The first version's segmented control marked the chosen answer with a
    // tint pale enough to read as disabled, and the theme's OutlinedButton
    // has no border at all.
    await _pump(tester, _event(), _FakeApi());

    for (final status in EventRsvpStatus.values) {
      expect(_filled(status), findsNothing);
      final button = tester.widget<ButtonStyleButton>(
        find.descendant(
          of: _answer(status),
          matching: find.byWidgetPredicate((w) => w is OutlinedButton),
        ),
      );
      final side = button.style!.side!.resolve(<WidgetState>{})!;
      expect(side.color, BisoPalette.light.primary);
      expect(side.width, greaterThanOrEqualTo(1.5));
    }
  });

  testWidgets('Going spans the row and the other two share the next', (
    tester,
  ) async {
    // Test text is Ahem, a full square per character and far wider than the
    // real font: at 390pt "Not going" measures 153 against 138 of room, so
    // the answers would stack. A wider screen gives the labels room; the next
    // test covers the stacked side.
    await _pump(tester, _event(), _FakeApi(), size: const Size(600, 844));

    final going = tester.getRect(_answer(EventRsvpStatus.going));
    final maybe = tester.getRect(_answer(EventRsvpStatus.maybe));
    final notGoing = tester.getRect(_answer(EventRsvpStatus.notGoing));
    expect(maybe.top, greaterThan(going.bottom));
    expect(maybe.top, notGoing.top);
    expect(maybe.width, notGoing.width);
    expect(maybe.width * 2, lessThan(going.width));
  });

  testWidgets('answers stack when the text is too large for half a row', (
    tester,
  ) async {
    await _pump(tester, _event(), _FakeApi(), textScale: 2);

    final going = tester.getRect(_answer(EventRsvpStatus.going));
    final maybe = tester.getRect(_answer(EventRsvpStatus.maybe));
    final notGoing = tester.getRect(_answer(EventRsvpStatus.notGoing));
    expect(maybe.width, going.width);
    expect(notGoing.width, going.width);
    expect(notGoing.top, greaterThan(maybe.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen readers hear which answer is chosen', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      _event(),
      _FakeApi(
        summary: const EventRsvpSummary(
          going: 4,
          maybe: 0,
          mine: EventRsvpStatus.going,
          open: true,
        ),
      ),
    );

    expect(
      tester.getSemantics(_answer(EventRsvpStatus.going)),
      isSemantics(
        isButton: true,
        isSelected: true,
        isInMutuallyExclusiveGroup: true,
        label: 'Going',
      ),
    );
    expect(
      tester.getSemantics(_answer(EventRsvpStatus.maybe)),
      isSemantics(isSelected: false, label: 'Maybe'),
    );
    semantics.dispose();
  });
}
