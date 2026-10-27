/// A member's answer to "Are you going?" for an event.
enum EventRsvpStatus { going, maybe, notGoing }

extension EventRsvpStatusWire on EventRsvpStatus {
  /// The value used on the wire and in the table.
  String get wire => switch (this) {
    EventRsvpStatus.going => 'going',
    EventRsvpStatus.maybe => 'maybe',
    EventRsvpStatus.notGoing => 'not_going',
  };

  static EventRsvpStatus? parse(Object? value) => switch (value) {
    'going' => EventRsvpStatus.going,
    'maybe' => EventRsvpStatus.maybe,
    'not_going' => EventRsvpStatus.notGoing,
    _ => null,
  };
}

/// Public RSVP numbers for one event plus the caller's own answer.
class EventRsvpSummary {
  const EventRsvpSummary({
    required this.going,
    required this.maybe,
    required this.mine,
    required this.open,
  });

  final int going;
  final int maybe;
  final EventRsvpStatus? mine;
  final bool open;

  static EventRsvpSummary? tryParse(Object? json) {
    if (json is! Map) return null;
    final counts = json['counts'];
    if (counts is! Map) return null;
    final going = counts['going'];
    final maybe = counts['maybe'];
    if (going is! num || maybe is! num) return null;
    return EventRsvpSummary(
      going: going.toInt(),
      maybe: maybe.toInt(),
      mine: EventRsvpStatusWire.parse(json['mine']),
      open: json['open'] == true,
    );
  }

  /// This summary with the caller's count moved to [next], for an instant
  /// UI update before the server answers. "Not going" is not counted.
  EventRsvpSummary withAnswer(EventRsvpStatus? next) {
    int delta(EventRsvpStatus status) =>
        (next == status ? 1 : 0) - (mine == status ? 1 : 0);
    final newGoing = going + delta(EventRsvpStatus.going);
    final newMaybe = maybe + delta(EventRsvpStatus.maybe);
    return EventRsvpSummary(
      going: newGoing < 0 ? 0 : newGoing,
      maybe: newMaybe < 0 ? 0 : newMaybe,
      mine: next,
      open: open,
    );
  }
}
