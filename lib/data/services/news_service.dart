import 'package:appwrite/appwrite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/appwrite_row.dart';
import '../models/news_model.dart';
import 'appwrite_service.dart';

class NewsService {
  /// National content shows on every campus, as on the web.
  static const _nationalCampusId = '5';

  /// Builds the query list for a news list read.
  ///
  /// Locale is resolved client-side; filtering `translation_refs.locale`
  /// would hide news that lacks that language.
  static List<String> buildNewsListQueries({
    String? campusId,
    int limit = 20,
    int offset = 0,
  }) {
    final queries = <String>[Query.equal('status', 'published')];

    if (campusId != null && campusId.isNotEmpty) {
      queries.add(
        Query.equal(
          'campus_id',
          campusId == _nationalCampusId
              ? [_nationalCampusId]
              : [campusId, _nationalCampusId],
        ),
      );
    }

    return [
      ...queries,
      Query.select(['*', 'translation_refs.*']),
      Query.orderDesc(r'$createdAt'),
      Query.limit(limit),
      Query.offset(offset),
    ];
  }

  /// Builds the query list for reading one article by [idOrSlug].
  static List<String> buildNewsLookupQueries(String idOrSlug) {
    return [
      Query.equal('status', 'published'),
      Query.or([Query.equal(r'$id', idOrSlug), Query.equal('slug', idOrSlug)]),
      Query.select(['*', 'translation_refs.*']),
      Query.limit(1),
    ];
  }

  Future<List<NewsModel>> listNews({
    String? campusId,
    String locale = 'no',
    int limit = 20,
    int offset = 0,
  }) async {
    final response = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: 'news',
      queries: buildNewsListQueries(
        campusId: campusId,
        limit: limit,
        offset: offset,
      ),
    );

    return response.rows
        .map((row) => NewsModel.fromAppwriteRow(rowData(row), locale: locale))
        .toList(growable: false);
  }

  /// One published article by its row id or slug, or null when there is none.
  Future<NewsModel?> getNews(String idOrSlug, {String locale = 'no'}) async {
    final response = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: 'news',
      queries: buildNewsLookupQueries(idOrSlug),
    );
    final row = response.rows.firstOrNull;
    return row == null
        ? null
        : NewsModel.fromAppwriteRow(rowData(row), locale: locale);
  }
}
