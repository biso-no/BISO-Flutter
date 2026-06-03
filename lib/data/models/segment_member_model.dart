import 'package:equatable/equatable.dart';

/// Links a user (and their attendee record) to an [EventSegment]. Backed by the
/// Appwrite `segment_members` collection in database `app`. Row security limits
/// reads to the owning user.
class SegmentMember extends Equatable {
  final String id;
  final String segmentId;
  final String eventId;
  final String userId;
  final String? attendeeId;
  final DateTime? assignedAt;

  const SegmentMember({
    required this.id,
    required this.segmentId,
    required this.eventId,
    required this.userId,
    this.attendeeId,
    this.assignedAt,
  });

  factory SegmentMember.fromMap(Map<String, dynamic> map) {
    return SegmentMember(
      id: (map['\$id'] ?? '').toString(),
      segmentId: (map['segment_id'] ?? '').toString(),
      eventId: (map['event_id'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      attendeeId: map['attendee_id']?.toString(),
      assignedAt: _parseDate(map['assigned_at']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  @override
  List<Object?> get props => [
    id,
    segmentId,
    eventId,
    userId,
    attendeeId,
    assignedAt,
  ];
}
