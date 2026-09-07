import 'package:appwrite/appwrite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/appwrite_row.dart';
import '../models/event_model.dart';
import 'appwrite_service.dart';

class EventService {
  TablesDB get _databases => db;

  /// Builds the query list for an events read.
  ///
  /// Locale is intentionally absent: filtering `translation_refs.locale`
  /// narrows parent rows rather than the nested array, which would hide
  /// events that lack that locale. Locale is resolved client-side instead.
  static List<String> buildEventQueries({
    String? campusId,
    int limit = 20,
    int offset = 0,
    bool includePast = false,
    String? search,
    DateTime? now,
  }) {
    final queries = <String>[
      Query.equal('status', 'published'),
      Query.select(['*', 'translation_refs.*']),
    ];

    if (campusId != null && campusId.isNotEmpty) {
      queries.add(Query.equal('campus_id', campusId));
    }

    if (!includePast) {
      final from = (now ?? DateTime.now().toUtc()).toIso8601String();
      queries.add(Query.greaterThanEqual('start_date', from));
    }

    final term = search?.trim() ?? '';
    if (term.isNotEmpty) {
      queries.add(Query.contains('translation_refs.title', [term]));
    }

    queries
      ..add(Query.orderAsc('start_date'))
      ..add(Query.limit(limit))
      ..add(Query.offset(offset));

    return queries;
  }

  /// Reads events directly from Appwrite, with server-side search and
  /// nested translations resolved client-side via [EventModel.fromAppwriteRow].
  Future<List<EventModel>> listEvents({
    String? campusId,
    String locale = 'no',
    int limit = 20,
    int offset = 0,
    bool includePast = false,
    String? search,
  }) async {
    final response = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: 'events',
      queries: buildEventQueries(
        campusId: campusId,
        limit: limit,
        offset: offset,
        includePast: includePast,
        search: search,
      ),
    );

    return response.rows
        .map((row) => EventModel.fromAppwriteRow(rowData(row), locale: locale))
        .toList(growable: false);
  }

  // Get single event by ID
  Future<EventModel?> getEventById(String eventId) async {
    try {
      final doc = await _databases.getRow(
        databaseId: AppConstants.databaseId,
        tableId: 'events',
        rowId: eventId,
      );

      return EventModel.fromMap(doc.data);
    } on AppwriteException catch (e) {
      if (e.code == 404) return null;
      throw EventException('Failed to fetch event: ${e.message}');
    } catch (e) {
      throw EventException('Network error occurred');
    }
  }

  // Create new event (admin/organizer function)
  Future<EventModel> createEvent(EventModel event) async {
    try {
      final doc = await _databases.createRow(
        databaseId: AppConstants.databaseId,
        tableId: 'events',
        rowId: ID.unique(),
        data: event.toMap(),
      );

      return EventModel.fromMap(doc.data);
    } on AppwriteException catch (e) {
      throw EventException('Failed to create event: ${e.message}');
    } catch (e) {
      throw EventException('Network error occurred');
    }
  }

  // Update event
  Future<EventModel> updateEvent(EventModel event) async {
    try {
      final doc = await _databases.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: 'events',
        rowId: event.id,
        data: event.toMap(),
      );

      return EventModel.fromMap(doc.data);
    } on AppwriteException catch (e) {
      throw EventException('Failed to update event: ${e.message}');
    } catch (e) {
      throw EventException('Network error occurred');
    }
  }

  // Register for event (if registration is required)
  Future<void> registerForEvent(String eventId, String userId) async {
    try {
      await _databases.createRow(
        databaseId: AppConstants.databaseId,
        tableId: 'event_registrations',
        rowId: ID.unique(),
        data: {
          'event_id': eventId,
          'user_id': userId,
          'registration_date': DateTime.now().toIso8601String(),
          'status': 'confirmed',
        },
      );

      // Update event attendee count
      final event = await getEventById(eventId);
      if (event != null) {
        await updateEvent(
          event.copyWith(currentAttendees: event.currentAttendees + 1),
        );
      }
    } on AppwriteException catch (e) {
      throw EventException('Failed to register for event: ${e.message}');
    } catch (e) {
      throw EventException('Network error occurred');
    }
  }

  // Cancel event registration
  Future<void> cancelEventRegistration(String eventId, String userId) async {
    try {
      final response = await _databases.listRows(
        databaseId: AppConstants.databaseId,
        tableId: 'event_registrations',
        queries: [
          Query.equal('event_id', eventId),
          Query.equal('user_id', userId),
        ],
      );

      if (response.rows.isNotEmpty) {
        await _databases.deleteRow(
          databaseId: AppConstants.databaseId,
          tableId: 'event_registrations',
          rowId: response.rows.first.$id,
        );

        // Update event attendee count
        final event = await getEventById(eventId);
        if (event != null) {
          await updateEvent(
            event.copyWith(
              currentAttendees: (event.currentAttendees - 1)
                  .clamp(0, double.infinity)
                  .toInt(),
            ),
          );
        }
      }
    } on AppwriteException catch (e) {
      throw EventException('Failed to cancel registration: ${e.message}');
    } catch (e) {
      throw EventException('Network error occurred');
    }
  }

  // Check if user is registered for event
  Future<bool> isUserRegistered(String eventId, String userId) async {
    try {
      final response = await _databases.listRows(
        databaseId: AppConstants.databaseId,
        tableId: 'event_registrations',
        queries: [
          Query.equal('event_id', eventId),
          Query.equal('user_id', userId),
        ],
      );

      return response.rows.isNotEmpty;
    } on AppwriteException catch (e) {
      throw EventException('Failed to check registration: ${e.message}');
    } catch (e) {
      throw EventException('Network error occurred');
    }
  }

  // Search events
  Future<List<EventModel>> searchEvents({
    required String query,
    String? campusId,
    String? category,
    int limit = AppConstants.defaultPageSize,
  }) async {
    try {
      List<String> queries = [
        Query.search('title', query),
        Query.limit(limit),
        Query.orderDesc('\$createdAt'),
      ];

      if (campusId != null) {
        queries.add(Query.equal('campus_id', campusId));
      }

      if (category != null) {
        queries.add(Query.contains('categories', category));
      }

      final response = await _databases.listRows(
        databaseId: AppConstants.databaseId,
        tableId: 'events',
        queries: queries,
      );

      return response.rows.map((doc) => EventModel.fromMap(doc.data)).toList();
    } on AppwriteException catch (e) {
      throw EventException('Failed to search events: ${e.message}');
    } catch (e) {
      throw EventException('Network error occurred');
    }
  }
}

class EventException implements Exception {
  final String message;
  EventException(this.message);

  @override
  String toString() => message;
}
