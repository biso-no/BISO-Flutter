import 'dart:async';

import 'package:biso/data/models/event_rsvp.dart';
import 'package:biso/data/services/event_rsvp_api_client.dart';
import 'package:biso/providers/events/event_rsvp_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = EventRsvpSummary(going: 4, maybe: 2, mine: null, open: true);

class _FakeRsvpApi implements EventRsvpApi {
  EventRsvpSummary summary = _base;
  EventRsvpSummary? respondResult;
  bool failFetch = false;
  bool failRespond = false;
  Completer<void>? holdRespond;
  int respondCalls = 0;

  @override
  Future<EventRsvpSummary> fetch(
    String eventId, {
    required bool signedIn,
  }) async {
    if (failFetch) {
      throw const EventRsvpApiException(EventRsvpApiErrorKind.network);
    }
    return summary;
  }

  @override
  Future<EventRsvpSummary> respond(
    String eventId,
    EventRsvpStatus? status,
  ) async {
    respondCalls++;
    await holdRespond?.future;
    if (failRespond) {
      throw const EventRsvpApiException(EventRsvpApiErrorKind.closed);
    }
    return respondResult ?? summary.withAnswer(status);
  }
}

Future<EventRsvpNotifier> _loaded(_FakeRsvpApi api) async {
  final notifier = EventRsvpNotifier(api, 'e1', signedIn: true);
  await pumpEventQueue();
  return notifier;
}

void main() {
  test('load fills the summary', () async {
    final notifier = await _loaded(_FakeRsvpApi());
    expect(notifier.state.summary?.going, 4);
    expect(notifier.state.loading, isFalse);
  });

  test('load failure leaves summary null', () async {
    final notifier = await _loaded(_FakeRsvpApi()..failFetch = true);
    expect(notifier.state.summary, isNull);
    expect(notifier.state.loading, isFalse);
  });

  test('respond shows the answer before the server answers', () async {
    final api = _FakeRsvpApi()..holdRespond = Completer<void>();
    final notifier = await _loaded(api);
    final future = notifier.respond(EventRsvpStatus.going);
    expect(notifier.state.summary!.mine, EventRsvpStatus.going);
    expect(notifier.state.summary!.going, 5);
    expect(notifier.state.saving, isTrue);
    api.holdRespond!.complete();
    expect(await future, isTrue);
    expect(notifier.state.saving, isFalse);
  });

  test("respond takes the server's summary", () async {
    final api = _FakeRsvpApi()
      ..respondResult = const EventRsvpSummary(
        going: 9,
        maybe: 0,
        mine: EventRsvpStatus.going,
        open: true,
      );
    final notifier = await _loaded(api);
    expect(await notifier.respond(EventRsvpStatus.going), isTrue);
    expect(notifier.state.summary!.going, 9);
  });

  test('reverts and reports failure', () async {
    final api = _FakeRsvpApi()..failRespond = true;
    final notifier = await _loaded(api);
    final before = notifier.state.summary!;
    expect(await notifier.respond(EventRsvpStatus.maybe), isFalse);
    final after = notifier.state.summary!;
    expect(after.going, before.going);
    expect(after.maybe, before.maybe);
    expect(after.mine, before.mine);
    expect(notifier.state.saving, isFalse);
  });

  test('ignores a second answer while one is saving', () async {
    final api = _FakeRsvpApi()..holdRespond = Completer<void>();
    final notifier = await _loaded(api);
    final first = notifier.respond(EventRsvpStatus.going);
    expect(await notifier.respond(EventRsvpStatus.maybe), isFalse);
    expect(api.respondCalls, 1);
    api.holdRespond!.complete();
    await first;
  });
}
