import 'package:appwrite/appwrite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/appwrite_row.dart';
import '../models/event_model.dart';
import 'appwrite_service.dart';

class EventService {
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
}

class EventException implements Exception {
  final String message;
  EventException(this.message);

  @override
  String toString() => message;
}
