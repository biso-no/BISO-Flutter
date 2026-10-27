import 'package:biso/data/models/event_rsvp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = EventRsvpSummary(
    going: 3,
    maybe: 1,
    mine: EventRsvpStatus.going,
    open: true,
  );

  test('tryParse reads counts, mine and open', () {
    final summary = EventRsvpSummary.tryParse({
      'counts': {'going': 3, 'maybe': 1},
      'mine': 'not_going',
      'open': true,
    });
    expect(summary, isNotNull);
    expect(summary!.going, 3);
    expect(summary.maybe, 1);
    expect(summary.mine, EventRsvpStatus.notGoing);
    expect(summary.open, isTrue);
  });

  test('tryParse returns null without counts', () {
    expect(EventRsvpSummary.tryParse({'mine': null, 'open': true}), isNull);
    expect(EventRsvpSummary.tryParse('nope'), isNull);
  });

  test('wire values round-trip', () {
    expect(EventRsvpStatus.notGoing.wire, 'not_going');
    expect(EventRsvpStatusWire.parse('maybe'), EventRsvpStatus.maybe);
    expect(EventRsvpStatusWire.parse('bogus'), isNull);
  });

  test('withAnswer going to maybe moves one count', () {
    final next = base.withAnswer(EventRsvpStatus.maybe);
    expect((next.going, next.maybe), (2, 2));
    expect(next.mine, EventRsvpStatus.maybe);
  });

  test('withAnswer null from going lowers going', () {
    final next = base.withAnswer(null);
    expect((next.going, next.maybe), (2, 1));
    expect(next.mine, isNull);
  });

  test('withAnswer notGoing to going raises going only', () {
    const start = EventRsvpSummary(
      going: 3,
      maybe: 1,
      mine: EventRsvpStatus.notGoing,
      open: true,
    );
    final next = start.withAnswer(EventRsvpStatus.going);
    expect((next.going, next.maybe), (4, 1));
  });
}
