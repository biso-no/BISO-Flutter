import 'package:appwrite/appwrite.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;

import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../models/event_model.dart';
import 'appwrite_service.dart';

class EventService {
  TablesDB get _databases => db;

  // Get events from WordPress API via Appwrite Function
  Future<List<EventModel>> getWordPressEvents({
    String? campusId,
    int limit = AppConstants.defaultPageSize,
    int offset = 0,
    bool includePast = false,
    String? search,
  }) async {
    final int page = (offset ~/ limit) + 1;
    return getFunctionEvents(
      campusId: campusId,
      limit: limit,
      page: page,
      includePast: includePast,
      search: search,
    );
  }

  // Get events via Appwrite Function which fetches from WordPress
  Future<List<EventModel>> getFunctionEvents({
    String? campusId,
    int limit = AppConstants.defaultPageSize,
    int offset = 0,
    int? page,
    bool includePast = false,
    String? search,
  }) async {
    try {
      final resolvedPage = page ?? ((offset ~/ limit) + 1);
      final shouldClientFilterByCampus =
          campusId != null && campusId.trim().isNotEmpty;
      final apiLimit = shouldClientFilterByCampus
          ? math.max(100, limit * resolvedPage)
          : limit;
      final apiPage = shouldClientFilterByCampus ? 1 : resolvedPage;
      final requestBody = {
        'campusId': campusId,
        'per_page': apiLimit,
        'page': apiPage,
        'include_past': includePast,
      };

      // Only include search when present and meets minimal length constraints
      final trimmedSearch = search?.trim();
      if (trimmedSearch != null && trimmedSearch.isNotEmpty) {
        requestBody['search'] = trimmedSearch;
      }

      final endpoint = '${AppConstants.apiUrl}/events';
      final stopwatch = Stopwatch()..start();
      AppLogger.api(
        'Fetching events from API',
        endpoint: endpoint,
        method: 'POST',
        extra: {
          'campus_id': campusId,
          'limit': limit,
          'api_limit': apiLimit,
          'offset': offset,
          'api_page': apiPage,
          'page': requestBody['page'],
          'client_filter_by_campus': shouldClientFilterByCampus,
          'include_past': includePast,
          'search': trimmedSearch,
        },
      );

      final execution = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      );
      stopwatch.stop();

      AppLogger.api(
        'Events API response received',
        endpoint: endpoint,
        method: 'POST',
        statusCode: execution.statusCode,
        extra: {
          'campus_id': campusId,
          'duration_ms': stopwatch.elapsedMilliseconds,
          'body_length': execution.body.length,
          if (execution.statusCode != 200)
            'body_preview': _preview(execution.body),
        },
      );

      if (execution.statusCode == 200) {
        final dynamic decoded = json.decode(execution.body);

        if (decoded is Map<String, dynamic>) {
          final List<dynamic> events =
              (decoded['events'] as List<dynamic>? ?? <dynamic>[]);
          final mapped = events
              .map(
                (e) => EventModel.fromFunctionEvent(
                  e as Map<String, dynamic>,
                  campusId: campusId ?? '',
                ),
              )
              .toList();
          final result = _applyCampusFilterAndPaging(
            mapped,
            campusId: campusId,
            limit: limit,
            page: resolvedPage,
            clientFiltered: shouldClientFilterByCampus,
          );
          AppLogger.info(
            '[EVENTS] Parsed API events map response',
            extra: {
              'campus_id': campusId,
              'raw_count': mapped.length,
              'count': result.length,
              'total_events': decoded['total_events'],
              'pagination': decoded['pagination']?.toString(),
              'client_filter_by_campus': shouldClientFilterByCampus,
              'sample_ids': result.take(3).map((event) => event.id).toList(),
            },
          );
          return result;
        }

        // Old format (array-only)
        if (decoded is List) {
          final models = decoded
              .map(
                (e) => EventModel.fromFunctionEvent(
                  e as Map<String, dynamic>,
                  campusId: campusId ?? '',
                ),
              )
              .toList();
          models.sort((a, b) => a.startDate.compareTo(b.startDate));
          final start = offset < models.length ? offset : models.length;
          final end = (start + limit) < models.length
              ? (start + limit)
              : models.length;
          final paged = models.sublist(start, end);
          final result = _applyCampusFilterAndPaging(
            shouldClientFilterByCampus ? models : paged,
            campusId: campusId,
            limit: limit,
            page: resolvedPage,
            clientFiltered: shouldClientFilterByCampus,
          );
          AppLogger.info(
            '[EVENTS] Parsed API events list response',
            extra: {
              'campus_id': campusId,
              'raw_count': paged.length,
              'count': result.length,
              'total_before_paging': models.length,
              'client_filter_by_campus': shouldClientFilterByCampus,
              'sample_ids': result.take(3).map((event) => event.id).toList(),
            },
          );
          return result;
        }

        AppLogger.warning(
          '[EVENTS] API returned unexpected response shape',
          extra: {
            'campus_id': campusId,
            'decoded_type': decoded.runtimeType.toString(),
            'body_preview': _preview(execution.body),
          },
        );
        throw EventException('Unexpected function response');
      } else {
        throw EventException(
          'Failed to fetch events (function): HTTP ${execution.statusCode}',
        );
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        '[EVENTS] API events fetch failed',
        error: error,
        stackTrace: stackTrace,
        extra: {
          'campus_id': campusId,
          'limit': limit,
          'offset': offset,
          'page': page,
          'include_past': includePast,
          'search': search,
        },
      );
      throw EventException('Error fetching events via function: $error');
    }
  }

  // Get total events count for a campus via Appwrite Function
  Future<int> getEventsTotalCount({
    required String campusId,
    bool includePast = false,
  }) async {
    try {
      final requestBody = {
        'campusId': campusId,
        'per_page': 1,
        'page': 1,
        'include_past': includePast,
      };

      final execution = await functions.createExecution(
        functionId: AppConstants.fnFetchEventsId,
        body: json.encode(requestBody),
      );

      if (execution.responseStatusCode == 200) {
        final dynamic decoded = json.decode(execution.responseBody);

        if (decoded is Map<String, dynamic>) {
          // New format
          if (decoded['total_events'] is int) {
            return decoded['total_events'] as int;
          }
          final pagination = decoded['pagination'];
          if (pagination is Map<String, dynamic> &&
              pagination['total_events'] is int) {
            return pagination['total_events'] as int;
          }
          // Old format fallback (no total provided)
          if (decoded['events'] is List) {
            return (decoded['events'] as List).length;
          }
        } else if (decoded is List) {
          // Old array-only format
          return decoded.length;
        }
      }

      throw EventException(
        'Failed to fetch events total: HTTP ${execution.responseStatusCode}',
      );
    } catch (e) {
      throw EventException('Error fetching events total: $e');
    }
  }

  // Get events from Appwrite database (internal events)
  Future<List<EventModel>> getAppwriteEvents({
    String? campusId,
    String? category,
    String? status,
    int limit = AppConstants.defaultPageSize,
    int offset = 0,
  }) async {
    try {
      List<String> queries = [
        Query.limit(limit),
        Query.offset(offset),
        Query.orderDesc('\$createdAt'),
      ];

      if (campusId != null) {
        queries.add(Query.equal('campus_id', campusId));
      }

      if (category != null) {
        queries.add(Query.contains('categories', category));
      }

      if (status != null) {
        queries.add(Query.equal('status', status));
      }

      AppLogger.info(
        '[EVENTS] Fetching Appwrite events',
        extra: {
          'database_id': AppConstants.databaseId,
          'table_id': 'events',
          'campus_id': campusId,
          'category': category,
          'status': status,
          'limit': limit,
          'offset': offset,
          'queries': queries,
        },
      );

      final response = await _databases.listRows(
        databaseId: AppConstants.databaseId,
        tableId: 'events',
        queries: queries,
      );

      final mapped = response.rows
          .map((doc) => EventModel.fromMap(doc.data))
          .toList();
      AppLogger.info(
        '[EVENTS] Appwrite events loaded',
        extra: {
          'campus_id': campusId,
          'count': mapped.length,
          'total': response.total,
          'sample_ids': mapped.take(3).map((event) => event.id).toList(),
        },
      );
      return mapped;
    } on AppwriteException catch (e) {
      AppLogger.error(
        '[EVENTS] Appwrite events fetch failed',
        error: e,
        extra: {
          'campus_id': campusId,
          'category': category,
          'status': status,
          'limit': limit,
          'offset': offset,
        },
      );
      throw EventException('Failed to fetch events: ${e.message}');
    } catch (error, stackTrace) {
      AppLogger.error(
        '[EVENTS] Appwrite events fetch failed',
        error: error,
        stackTrace: stackTrace,
        extra: {
          'campus_id': campusId,
          'category': category,
          'status': status,
          'limit': limit,
          'offset': offset,
        },
      );
      throw EventException('Network error occurred');
    }
  }

  // Get all events (combined WordPress + Appwrite)
  Future<List<EventModel>> getAllEvents({
    String? campusId,
    String? category,
    String? status,
    int limit = AppConstants.defaultPageSize,
    int offset = 0,
  }) async {
    // Since we don't use Appwrite events collection, rely solely on WordPress
    return getWordPressEvents(campusId: campusId, limit: limit, offset: offset);
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

  String _preview(String body) {
    const maxLength = 500;
    if (body.length <= maxLength) return body;
    return '${body.substring(0, maxLength)}...';
  }

  List<EventModel> _applyCampusFilterAndPaging(
    List<EventModel> events, {
    required String? campusId,
    required int limit,
    required int page,
    required bool clientFiltered,
  }) {
    if (!clientFiltered || campusId == null || campusId.trim().isEmpty) {
      return events;
    }

    final filtered = events
        .where((event) => _matchesCampus(event, campusId))
        .toList(growable: false);
    final start = (page - 1) * limit;
    if (start >= filtered.length) return const <EventModel>[];
    final end = math.min(start + limit, filtered.length);
    return filtered.sublist(start, end);
  }

  bool _matchesCampus(EventModel event, String campusId) {
    return _campusMatchers(campusId).contains(event.campusId.toLowerCase());
  }

  Set<String> _campusMatchers(String campusId) {
    switch (campusId) {
      case AppConstants.osloId:
        return const {'1', 'oslo', 'campus-oslo'};
      case AppConstants.bergenId:
        return const {'2', 'bergen', 'campus-bergen'};
      case AppConstants.trondheimId:
        return const {'3', 'trondheim', 'campus-trondheim'};
      case AppConstants.stavangerId:
        return const {'4', 'stavanger', 'campus-stavanger'};
      default:
        return {campusId.toLowerCase().trim()};
    }
  }
}

class EventException implements Exception {
  final String message;
  EventException(this.message);

  @override
  String toString() => message;
}
