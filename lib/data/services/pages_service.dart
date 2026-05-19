import 'dart:convert';
import 'package:appwrite/appwrite.dart';

import '../../core/constants/app_constants.dart';
import '../services/appwrite_service.dart';

class PagesService {
  /// Returns the ordered list of published blocks for a department,
  /// or an empty list if no published page exists.
  Future<List<Map<String, dynamic>>> getPublishedBlocksForDepartment(
    String departmentId,
  ) async {
    try {
      final result = await db.listRows(
        databaseId: AppConstants.pagesDatabaseId,
        tableId: AppConstants.pagesCollectionId,
        queries: [
          Query.equal('department', departmentId),
          Query.equal('status', 'published'),
          Query.limit(1),
        ],
      );

      final row = result.rows.firstOrNull;
      if (row == null) return [];

      final doc = jsonDecode(row.data['doc'] as String) as Map<String, dynamic>;
      final blocks = doc['blocks'] as List<dynamic>? ?? [];
      return blocks.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }
}
