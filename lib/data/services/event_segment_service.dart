import 'package:appwrite/appwrite.dart';

import '../../core/constants/app_constants.dart';
import '../models/event_segment_model.dart';
import '../models/segment_member_model.dart';
import 'appwrite_service.dart';

/// Reads the signed-in user's event logistics ("Your trip") from the Appwrite
/// `segment_members` and `event_segments` collections in database `app`.
///
/// Uses the shared [db] (`TablesDB`) singleton from [appwrite_service.dart],
/// mirroring [NotificationInboxService] and [EventService].
class EventSegmentService {
  static const String _segmentsTable = 'event_segments';
  static const String _membersTable = 'segment_members';
  static const int _fetchLimit = 25;

  /// Fetch the segment(s) the [userId] is assigned to for [eventId].
  ///
  /// Returns an empty list when the user has no assignments. Resolves the
  /// owned `segment_members` rows first (row security scopes them to the user),
  /// then loads the matching `event_segments` definitions.
  Future<List<EventSegment>> fetchMyTrip({
    required String eventId,
    required String userId,
  }) async {
    try {
      final memberRows = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: _membersTable,
        queries: [
          Query.equal('user_id', userId),
          Query.equal('event_id', eventId),
          Query.limit(_fetchLimit),
        ],
      );

      final segmentIds = <String>[];
      for (final row in memberRows.rows) {
        final segmentId = row.data['segment_id'] as String?;
        if (segmentId != null && segmentId.isNotEmpty) {
          segmentIds.add(segmentId);
        }
      }

      if (segmentIds.isEmpty) return const <EventSegment>[];

      final segmentRows = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: _segmentsTable,
        queries: [
          Query.equal('\$id', segmentIds),
          Query.limit(_fetchLimit),
        ],
      );

      return segmentRows.rows
          .map((row) => EventSegment.fromMap(row.data))
          .toList();
    } on AppwriteException catch (e) {
      throw EventSegmentException('Failed to load trip: ${e.message}');
    } catch (e) {
      throw EventSegmentException('Failed to load trip: $e');
    }
  }

  /// Best-effort fetch of the members of [segmentId] (e.g. roommates / bus-mates).
  ///
  /// Row security may restrict results to the caller's own row, so callers
  /// should treat this as optional and never block the "Your trip" card on it.
  /// Returns an empty list on any error rather than throwing.
  Future<List<SegmentMember>> fetchSegmentMembers(String segmentId) async {
    try {
      final rows = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: _membersTable,
        queries: [
          Query.equal('segment_id', segmentId),
          Query.limit(_fetchLimit),
        ],
      );

      return rows.rows.map((row) => SegmentMember.fromMap(row.data)).toList();
    } catch (_) {
      return const <SegmentMember>[];
    }
  }
}

class EventSegmentException implements Exception {
  final String message;
  EventSegmentException(this.message);

  @override
  String toString() => message;
}
