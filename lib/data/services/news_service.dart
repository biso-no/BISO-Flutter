import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/content_locale.dart';
import '../models/news_model.dart';

class NewsException implements Exception {
  final String message;
  NewsException(this.message);

  @override
  String toString() => message;
}

class NewsService {
  Future<List<NewsModel>> getNews({
    String? campusId,
    int limit = AppConstants.defaultPageSize,
    int page = 1,
    String? search,
  }) async {
    try {
      final locale = await ContentLocale.current();
      final requestBody = {
        'campusId': campusId,
        'per_page': limit,
        'page': page,
        'locale': locale,
        if (search != null && search.trim().isNotEmpty)
          'search': search.trim(),
      };
      final endpoint = '${AppConstants.apiUrl}/news';
      final stopwatch = Stopwatch()..start();

      AppLogger.api(
        'Fetching news from API',
        endpoint: endpoint,
        method: 'POST',
        extra: {
          'campus_id': campusId,
          'limit': limit,
          'page': page,
          'locale': locale,
          'search': search,
        },
      );

      final response = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      );
      stopwatch.stop();

      AppLogger.api(
        'News API response received',
        endpoint: endpoint,
        method: 'POST',
        statusCode: response.statusCode,
        extra: {
          'campus_id': campusId,
          'duration_ms': stopwatch.elapsedMilliseconds,
          'body_length': response.body.length,
        },
      );

      if (response.statusCode != 200) {
        throw NewsException(
          'Failed to fetch news: HTTP ${response.statusCode}',
        );
      }

      final dynamic decoded = json.decode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw NewsException('Unexpected news response shape');
      }

      final items = (decoded['news'] as List<dynamic>? ?? <dynamic>[])
          .map((item) => NewsModel.fromBisoApi(item as Map<String, dynamic>))
          .toList(growable: false);

      // Keep sticky articles at the top of the feed.
      final sticky = items.where((item) => item.sticky).toList();
      final regular = items.where((item) => !item.sticky).toList();
      final result = [...sticky, ...regular];

      AppLogger.info(
        '[NEWS] Parsed news response',
        extra: {
          'campus_id': campusId,
          'count': result.length,
          'total_news': decoded['total_news'],
          'sample_ids': result.take(3).map((item) => item.id).toList(),
        },
      );
      return result;
    } on NewsException {
      rethrow;
    } catch (error, stackTrace) {
      AppLogger.error(
        '[NEWS] News fetch failed',
        error: error,
        stackTrace: stackTrace,
        extra: {'campus_id': campusId, 'limit': limit, 'page': page},
      );
      throw NewsException('Error fetching news: $error');
    }
  }

  /// Fetches a single article by id.
  ///
  /// The API has no by-id endpoint, so this scans the first pages of the
  /// campus-agnostic feed. Used for deep links; regular navigation passes
  /// the full model.
  Future<NewsModel?> getNewsItem(String id, {int maxPages = 3}) async {
    for (var page = 1; page <= maxPages; page++) {
      final items = await getNews(limit: 50, page: page);
      for (final item in items) {
        if (item.id == id) return item;
      }
      if (items.length < 50) break;
    }
    return null;
  }
}
