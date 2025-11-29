import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
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
      final requestBody = {
        'campusId': campusId,
        'per_page': limit,
        'page': page,
        'includeExpired': includeExpired,
        if (departmentId != null) 'departmentId': departmentId,
        if (verv != null) 'verv': verv,
      };

      final execution = await http.post(
        Uri.parse('${AppConstants.apiUrl}/jobs'),
        body: json.encode(requestBody),
      );

      if (execution.statusCode == 200) {
        final dynamic decoded = json.decode(execution.body);

        if (decoded is Map<String, dynamic>) {
          final List<dynamic> jobs = (decoded['jobs'] as List<dynamic>? ?? <dynamic>[]);
          return jobs
              .map((j) => JobModel.fromFunctionJob(
                    j as Map<String, dynamic>,
                    campusId: campusId ?? '',
                  ))
              .toList(growable: false);
        }
        if (decoded is List) {
          return decoded
              .map((j) => JobModel.fromFunctionJob(
                    j as Map<String, dynamic>,
                    campusId: campusId ?? '',
                  ))
              .toList(growable: false);
        }
      }
    } catch (e) {
      // Fallback to internal DB if function fails
    }

    // Fallback: internal Appwrite collection
    final List<String> queries = [
      Query.orderDesc('\$createdAt'),
      Query.limit(limit),
      Query.offset((page - 1) * limit),
    ];

    if (campusId != null) queries.add(Query.equal('campus_id', campusId));
    if (!includeExpired) queries.add(Query.equal('status', 'open'));

    final results = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: collectionId,
      queries: queries,
    );

    return results.rows
        .map((doc) => JobModel.fromMap(doc.data))
        .toList(growable: false);
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
          if (pagination is Map<String, dynamic> && pagination['total_jobs'] is int) {
            return pagination['total_jobs'] as int;
          }
          if (decoded['jobs'] is List) return (decoded['jobs'] as List).length;
        } else if (decoded is List) {
          return decoded.length;
        }
      }
      throw Exception('Failed to fetch jobs total: HTTP ${execution.responseStatusCode}');
    } catch (_) {
      // Fallback: estimate from DB (not accurate for WP source)
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
        return res.total;
      } catch (_) {
        return 0;
      }
    }
  }
}
