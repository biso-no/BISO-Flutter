import 'package:appwrite/appwrite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/appwrite_row.dart';
import '../models/job_model.dart';
import 'appwrite_service.dart';

class JobService {
  static const String collectionId = 'jobs';

  /// The filter clauses every jobs read shares, list and count alike.
  ///
  /// Locale is intentionally absent: filtering `translations.locale`
  /// narrows parent rows rather than the nested array. 73% of live jobs
  /// are Norwegian-only and 21% English-only, so such a filter would hide
  /// most of the board from every user. Locale is resolved client-side.
  static List<String> _jobFilters({
    String? campusId,
    bool includeExpired = false,
    String? search,
    DateTime? now,
  }) {
    final queries = <String>[Query.equal('status', 'published')];

    if (campusId != null && campusId.isNotEmpty) {
      queries.add(Query.equal('campus_id', campusId));
    }

    if (!includeExpired) {
      final from = (now ?? DateTime.now().toUtc()).toIso8601String();
      // A job with no deadline is open-ended, not expired.
      queries.add(
        Query.or([
          Query.greaterThanEqual('application_deadline', from),
          Query.isNull('application_deadline'),
        ]),
      );
    }

    final term = search?.trim() ?? '';
    if (term.isNotEmpty) {
      queries.add(Query.contains('translations.title', [term]));
    }

    return queries;
  }

  /// Builds the query list for a jobs read.
  static List<String> buildJobQueries({
    String? campusId,
    int limit = 20,
    int offset = 0,
    bool includeExpired = false,
    String? search,
    DateTime? now,
  }) {
    return [
      ..._jobFilters(
        campusId: campusId,
        includeExpired: includeExpired,
        search: search,
        now: now,
      ),
      // Nested translations are only returned when explicitly selected.
      Query.select(['*', 'translations.*']),
      // Soonest deadline first, regardless of includeExpired: results must
      // always come back in a deterministic order.
      Query.orderAsc('application_deadline'),
      Query.limit(limit),
      Query.offset(offset),
    ];
  }

  /// Builds the query list for a count-only jobs read.
  ///
  /// Same filters as [buildJobQueries], but selects just `$id` and asks for
  /// a single row: the caller reads `total`, never the rows, and
  /// Appwrite's `total` is the full match count independent of `limit`.
  static List<String> buildJobCountQueries({
    String? campusId,
    bool includeExpired = false,
    DateTime? now,
  }) {
    return [
      ..._jobFilters(
        campusId: campusId,
        includeExpired: includeExpired,
        now: now,
      ),
      Query.select([r'$id']),
      Query.limit(1),
    ];
  }

  /// Reads jobs directly from Appwrite, with server-side search and nested
  /// translations resolved client-side via [JobModel.fromAppwriteRow].
  Future<List<JobModel>> listJobs({
    String? campusId,
    String locale = 'no',
    int limit = 20,
    int offset = 0,
    bool includeExpired = false,
    String? search,
  }) async {
    final response = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      queries: buildJobQueries(
        campusId: campusId,
        limit: limit,
        offset: offset,
        includeExpired: includeExpired,
        search: search,
      ),
    );

    return response.rows
        .map((row) => JobModel.fromAppwriteRow(rowData(row), locale: locale))
        .toList(growable: false);
  }

  /// How many jobs match the same filters [listJobs] uses.
  Future<int> countJobs({String? campusId, bool includeExpired = false}) async {
    final response = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      queries: buildJobCountQueries(
        campusId: campusId,
        includeExpired: includeExpired,
      ),
    );
    return response.total;
  }
}
