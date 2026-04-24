import 'dart:convert';
import 'dart:math' as math;
import 'package:appwrite/appwrite.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../models/job_model.dart';
import 'appwrite_service.dart';

class JobService {
  static const String collectionId = 'jobs';

  Future<List<JobModel>> getLatestJobs({
    String? campusId,
    int limit = 10,
    int page = 1,
    bool includeExpired = false,
    String? departmentId,
    String? verv,
  }) async {
    // Prefer Appwrite Function (WordPress-backed)
    try {
      final shouldClientFilterByCampus =
          campusId != null && campusId.trim().isNotEmpty;
      final apiLimit = shouldClientFilterByCampus
          ? math.max(100, limit * page)
          : limit;
      final apiPage = shouldClientFilterByCampus ? 1 : page;
      final requestBody = {
        'campusId': campusId,
        'per_page': apiLimit,
        'page': apiPage,
        'includeExpired': includeExpired,
        if (departmentId != null) 'departmentId': departmentId,
        if (verv != null) 'verv': verv,
      };
      final endpoint = '${AppConstants.apiUrl}/jobs';
      final stopwatch = Stopwatch()..start();

      AppLogger.api(
        'Fetching jobs from API',
        endpoint: endpoint,
        method: 'POST',
        extra: {
          'campus_id': campusId,
          'limit': limit,
          'page': page,
          'api_limit': apiLimit,
          'api_page': apiPage,
          'client_filter_by_campus': shouldClientFilterByCampus,
          'include_expired': includeExpired,
          'department_id': departmentId,
          'verv': verv,
        },
      );

      final execution = await http.post(
        Uri.parse(endpoint),
        body: json.encode(requestBody),
      );
      stopwatch.stop();

      AppLogger.api(
        'Jobs API response received',
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
          final List<dynamic> jobs =
              (decoded['jobs'] as List<dynamic>? ?? <dynamic>[]);
          final mapped = jobs
              .map(
                (j) => JobModel.fromFunctionJob(
                  j as Map<String, dynamic>,
                  campusId: campusId ?? '',
                ),
              )
              .toList(growable: false);
          final result = _applyCampusFilterAndPaging(
            mapped,
            campusId: campusId,
            limit: limit,
            page: page,
            clientFiltered: shouldClientFilterByCampus,
          );
          AppLogger.info(
            '[JOBS] Parsed API jobs map response',
            extra: {
              'campus_id': campusId,
              'raw_count': mapped.length,
              'count': result.length,
              'total_jobs': decoded['total_jobs'],
              'pagination': decoded['pagination']?.toString(),
              'client_filter_by_campus': shouldClientFilterByCampus,
              'sample_ids': result.take(3).map((job) => job.id).toList(),
            },
          );
          return result;
        }
        if (decoded is List) {
          final mapped = decoded
              .map(
                (j) => JobModel.fromFunctionJob(
                  j as Map<String, dynamic>,
                  campusId: campusId ?? '',
                ),
              )
              .toList(growable: false);
          final result = _applyCampusFilterAndPaging(
            mapped,
            campusId: campusId,
            limit: limit,
            page: page,
            clientFiltered: shouldClientFilterByCampus,
          );
          AppLogger.info(
            '[JOBS] Parsed API jobs list response',
            extra: {
              'campus_id': campusId,
              'raw_count': mapped.length,
              'count': result.length,
              'client_filter_by_campus': shouldClientFilterByCampus,
              'sample_ids': result.take(3).map((job) => job.id).toList(),
            },
          );
          return result;
        }

        AppLogger.warning(
          '[JOBS] API returned unexpected response shape; falling back to Appwrite',
          extra: {
            'campus_id': campusId,
            'decoded_type': decoded.runtimeType.toString(),
            'body_preview': _preview(execution.body),
          },
        );
      } else {
        AppLogger.warning(
          '[JOBS] API returned non-200; falling back to Appwrite',
          extra: {
            'campus_id': campusId,
            'status_code': execution.statusCode,
            'body_preview': _preview(execution.body),
          },
        );
      }
    } catch (error, stackTrace) {
      // Fallback to internal DB if function fails
      AppLogger.warning(
        '[JOBS] API jobs fetch failed; falling back to Appwrite',
        error: error,
        stackTrace: stackTrace,
        extra: {'campus_id': campusId, 'limit': limit, 'page': page},
      );
    }

    // Fallback: internal Appwrite collection
    final List<String> queries = [
      Query.orderDesc('\$createdAt'),
      Query.limit(limit),
      Query.offset((page - 1) * limit),
    ];

    if (campusId != null) queries.add(Query.equal('campus_id', campusId));
    if (!includeExpired) queries.add(Query.equal('status', 'open'));

    AppLogger.info(
      '[JOBS] Fetching jobs from Appwrite fallback',
      extra: {
        'database_id': AppConstants.databaseId,
        'table_id': collectionId,
        'campus_id': campusId,
        'limit': limit,
        'page': page,
        'queries': queries,
      },
    );

    final results = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      queries: queries,
    );

    final mapped = results.rows
        .map((doc) => JobModel.fromMap(doc.data))
        .toList(growable: false);
    AppLogger.info(
      '[JOBS] Appwrite fallback jobs loaded',
      extra: {
        'campus_id': campusId,
        'count': mapped.length,
        'total': results.total,
        'sample_ids': mapped.take(3).map((job) => job.id).toList(),
      },
    );
    return mapped;
  }

  Future<int> getJobsTotalCount({
    required String campusId,
    bool includeExpired = false,
    String? departmentId,
    String? verv,
  }) async {
    try {
      final requestBody = {
        'campusId': campusId,
        'per_page': 1,
        'page': 1,
        'includeExpired': includeExpired,
        if (departmentId != null) 'departmentId': departmentId,
        if (verv != null) 'verv': verv,
      };

      final execution = await functions.createExecution(
        functionId: AppConstants.fnFetchJobsId,
        xasync: false,
        body: json.encode(requestBody),
      );

      if (execution.responseStatusCode == 200) {
        final dynamic decoded = json.decode(execution.responseBody);
        if (decoded is Map<String, dynamic>) {
          if (decoded['total_jobs'] is int) return decoded['total_jobs'] as int;
          final pagination = decoded['pagination'];
          if (pagination is Map<String, dynamic> &&
              pagination['total_jobs'] is int) {
            return pagination['total_jobs'] as int;
          }
          if (decoded['jobs'] is List) return (decoded['jobs'] as List).length;
        } else if (decoded is List) {
          return decoded.length;
        }
      }
      throw Exception(
        'Failed to fetch jobs total: HTTP ${execution.responseStatusCode}',
      );
    } catch (error, stackTrace) {
      // Fallback: estimate from DB (not accurate for WP source)
      AppLogger.warning(
        '[JOBS] Total count API fetch failed; estimating from Appwrite',
        error: error,
        stackTrace: stackTrace,
        extra: {'campus_id': campusId},
      );
      try {
        final res = await db.listRows(
          databaseId: AppConstants.databaseId,
          tableId: collectionId,
          queries: [
            Query.equal('campus_id', campusId),
            if (!includeExpired) Query.equal('status', 'open'),
            Query.limit(1),
          ],
        );
        AppLogger.info(
          '[JOBS] Total count estimated from Appwrite',
          extra: {'campus_id': campusId, 'total': res.total},
        );
        return res.total;
      } catch (fallbackError, fallbackStackTrace) {
        AppLogger.error(
          '[JOBS] Total count fallback failed',
          error: fallbackError,
          stackTrace: fallbackStackTrace,
          extra: {'campus_id': campusId},
        );
        return 0;
      }
    }
  }

  String _preview(String body) {
    const maxLength = 500;
    if (body.length <= maxLength) return body;
    return '${body.substring(0, maxLength)}...';
  }

  List<JobModel> _applyCampusFilterAndPaging(
    List<JobModel> jobs, {
    required String? campusId,
    required int limit,
    required int page,
    required bool clientFiltered,
  }) {
    if (!clientFiltered || campusId == null || campusId.trim().isEmpty) {
      return jobs;
    }

    final filtered = jobs
        .where((job) => _matchesCampus(job, campusId))
        .toList(growable: false);
    final start = (page - 1) * limit;
    if (start >= filtered.length) return const <JobModel>[];
    final end = math.min(start + limit, filtered.length);
    return filtered.sublist(start, end);
  }

  bool _matchesCampus(JobModel job, String campusId) {
    final matchers = _campusMatchers(campusId);
    final values =
        <String>[
              job.campusId,
              ..._metadataStrings(job.metadata['campusNames']),
              ..._metadataStrings(job.metadata['campusSlugs']),
            ]
            .map((value) => value.toLowerCase().trim())
            .where((value) => value.isNotEmpty);

    return values.any(matchers.contains);
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

  List<String> _metadataStrings(Object? value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList(growable: false);
    }
    if (value == null) return const <String>[];
    final stringValue = value.toString();
    return stringValue.isEmpty ? const <String>[] : <String>[stringValue];
  }
}
