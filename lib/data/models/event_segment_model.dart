import 'dart:convert';

import 'package:equatable/equatable.dart';

/// A logistics segment a student can be assigned to for a (large) event, e.g.
/// a bus with a departure time or a hotel room. Backed by the Appwrite
/// `event_segments` collection in database `app`.
class EventSegment extends Equatable {
  final String id;
  final String eventId;
  final String kind; // free string, e.g. "transport" / "lodging"
  final String name; // e.g. "Oslo Bus 2", "Room 214"
  final String? campusId;
  final int capacity;

  /// Arbitrary key/value details parsed from the stored JSON string. Keys are
  /// not fixed (departure_time, pickup_location, hotel, room_number, schedule,
  /// notes, …). Always a map — tolerates null/invalid input by yielding `{}`.
  final Map<String, dynamic> metadata;
  final String? topicId;

  const EventSegment({
    required this.id,
    required this.eventId,
    required this.kind,
    required this.name,
    this.campusId,
    this.capacity = 0,
    this.metadata = const <String, dynamic>{},
    this.topicId,
  });

  factory EventSegment.fromMap(Map<String, dynamic> map) {
    return EventSegment(
      id: (map['\$id'] ?? '').toString(),
      eventId: (map['event_id'] ?? '').toString(),
      kind: (map['kind'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      campusId: map['campus_id']?.toString(),
      capacity: _parseInt(map['capacity']),
      metadata: _parseMetadata(map['metadata']),
      topicId: map['topic_id']?.toString(),
    );
  }

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  /// Parses the `metadata` attribute which is stored as a JSON string. Tolerates
  /// null, empty, an already-decoded map, or invalid JSON by returning `{}`.
  static Map<String, dynamic> _parseMetadata(dynamic value) {
    if (value == null) return const <String, dynamic>{};
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, dynamic v) => MapEntry(key.toString(), v));
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return const <String, dynamic>{};
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) {
          return decoded.map((key, dynamic v) => MapEntry(key.toString(), v));
        }
      } catch (_) {
        // Invalid JSON — fall through to empty map.
      }
    }
    return const <String, dynamic>{};
  }

  @override
  List<Object?> get props => [
    id,
    eventId,
    kind,
    name,
    campusId,
    capacity,
    metadata,
    topicId,
  ];
}
