import 'package:appwrite/appwrite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/appwrite_row.dart';
import '../models/event_model.dart';
import 'appwrite_service.dart';

class EventService {
  /// The filter clauses every events read shares, list and count alike.
  ///
  /// Locale is intentionally absent: filtering `translation_refs.locale`
  /// narrows parent rows rather than the nested array, which would hide
  /// events that lack that locale. Locale is resolved client-side instead.
  static List<String> _eventFilters({
    String? campusId,
    bool includePast = false,
    String? search,
    DateTime? now,
  }) {
    final queries = <String>[Query.equal('status', 'published')];

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

    return queries;
  }

  /// Builds the query list for an events read.
  static List<String> buildEventQueries({
    String? campusId,
    int limit = 20,
    int offset = 0,
    bool includePast = false,
    String? search,
    DateTime? now,
  }) {
    return [
      ..._eventFilters(
        campusId: campusId,
        includePast: includePast,
        search: search,
        now: now,
      ),
      // Nested translations are only returned when explicitly selected.
      Query.select(['*', 'translation_refs.*']),
      Query.orderAsc('start_date'),
      Query.limit(limit),
      Query.offset(offset),
    ];
  }

  /// Builds the query list for a count-only events read.
  ///
  /// Same filters as [buildEventQueries], but selects just `$id` and asks
  /// for a single row: the caller reads `total`, never the rows, and
  /// Appwrite's `total` is the full match count independent of `limit`.
  /// Inheriting `select(['*', 'translation_refs.*'])` here would fetch a
  /// whole row plus its expanded relations to read one integer.
  static List<String> buildEventCountQueries({
    String? campusId,
    bool includePast = false,
    DateTime? now,
  }) {
    return [
      ..._eventFilters(
        campusId: campusId,
        includePast: includePast,
        now: now,
      ),
      Query.select([r'$id']),
      Query.limit(1),
    ];
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

  /// How many events match the same filters [listEvents] uses.
  ///
  /// Callers that need a stat should use this rather than issuing their own
  /// `listRows` on `events` and threading [buildEventQueries] in by hand;
  /// the query shape stays in one place.
  Future<int> countEvents({String? campusId, bool includePast = false}) async {
    final response = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: 'events',
      queries: buildEventCountQueries(
        campusId: campusId,
        includePast: includePast,
      ),
    );

    return response.total;
  }
}

class EventException implements Exception {
  final String message;
  EventException(this.message);

  @override
  String toString() => message;
}
