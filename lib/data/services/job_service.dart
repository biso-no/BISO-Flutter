import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/content_locale.dart';
import '../models/job_model.dart';

class JobException implements Exception {
  final String message;
  JobException(this.message);

  @override
  String toString() => message;
}

class JobService {
  Future<List<JobModel>> getLatestJobs({
    String? campusId,
    int limit = 10,
    int page = 1,
    bool includeExpired = false,
    String? departmentId,
    String? verv,
    String? search,
  }) async {
    try {
      final locale = await ContentLocale.current();
      final requestBody = {
        'campusId': campusId,
        'per_page': limit,
        'page': page,
        'includeExpired': includeExpired,
        'locale': locale,
        if (departmentId != null) 'departmentId': departmentId,
        if (verv != null) 'verv': verv,
        if (search != null && search.trim().isNotEmpty)
          'search': search.trim(),
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
          'include_expired': includeExpired,
          'department_id': departmentId,
          'locale': locale,
          'search': search,
        },
      );

      final execution = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
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

      if (execution.statusCode != 200) {
        throw JobException(
          'Failed to fetch jobs: HTTP ${execution.statusCode}',
        );
      }

      final dynamic decoded = json.decode(execution.body);

      if (decoded is Map<String, dynamic>) {
        final isBisoSource = decoded['source'] == 'biso';
        final List<dynamic> jobs =
            (decoded['jobs'] as List<dynamic>? ?? <dynamic>[]);

        // BISO Sites source: campus filtering, locale resolution, and
        // pagination all happen server-side.
        if (isBisoSource) {
          final result = jobs
              .map((j) => JobModel.fromBisoApi(j as Map<String, dynamic>))
              .toList(growable: false);
          AppLogger.info(
            '[JOBS] Parsed BISO Sites jobs response',
            extra: {
              'campus_id': campusId,
              'count': result.length,
              'total_jobs': decoded['total_jobs'],
              'sample_ids': result.take(3).map((job) => job.id).toList(),
            },
          );
          return result;
        }

        // Legacy WordPress proxy: campus metadata is unreliable, so filter
        // client-side over the returned page.
        final mapped = jobs
            .map(
              (j) => JobModel.fromFunctionJob(
                j as Map<String, dynamic>,
                campusId: campusId ?? '',
              ),
            )
            .toList(growable: false);
        final result = _applyCampusFilter(mapped, campusId: campusId);
        AppLogger.info(
          '[JOBS] Parsed API jobs map response',
          extra: {
            'campus_id': campusId,
            'raw_count': mapped.length,
            'count': result.length,
            'total_jobs': decoded['total_jobs'],
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
        final result = _applyCampusFilter(mapped, campusId: campusId);
        AppLogger.info(
          '[JOBS] Parsed API jobs list response',
          extra: {
            'campus_id': campusId,
            'raw_count': mapped.length,
            'count': result.length,
            'sample_ids': result.take(3).map((job) => job.id).toList(),
          },
        );
        return result;
      }

      throw JobException('Unexpected jobs response shape');
    } on JobException {
      rethrow;
    } catch (error, stackTrace) {
      AppLogger.error(
        '[JOBS] API jobs fetch failed',
        error: error,
        stackTrace: stackTrace,
        extra: {'campus_id': campusId, 'limit': limit, 'page': page},
      );
      throw JobException('Error fetching jobs: $error');
    }
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

      final response = await http.post(
        Uri.parse('${AppConstants.apiUrl}/jobs'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final dynamic decoded = json.decode(response.body);
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
      throw JobException(
        'Failed to fetch jobs total: HTTP ${response.statusCode}',
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        '[JOBS] Total count fetch failed',
        error: error,
        stackTrace: stackTrace,
        extra: {'campus_id': campusId},
      );
      return 0;
    }
  }

  String _preview(String body) {
    const maxLength = 500;
    if (body.length <= maxLength) return body;
    return '${body.substring(0, maxLength)}...';
  }

  List<JobModel> _applyCampusFilter(
    List<JobModel> jobs, {
    required String? campusId,
  }) {
    if (campusId == null || campusId.trim().isEmpty) {
      return jobs;
    }

    return jobs
        .where((job) => _matchesCampus(job, campusId))
        .toList(growable: false);
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
