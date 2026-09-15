import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;

import '../../core/constants/app_constants.dart';
import '../models/department_model.dart';
import '../services/appwrite_service.dart';

class DepartmentService {
  static const String collectionId = AppConstants.departmentsCollectionId;

  /// Lists from `departments`, not `content_translations`: most departments
  /// have no translation row, and listing from translations hid them.
  Future<List<DepartmentModel>> getActiveDepartmentsForCampus(
    String campusId, {
    String locale = 'en',
  }) async {
    final results = await Future.wait([
      db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: collectionId,
        queries: [
          Query.equal('campus_id', campusId),
          Query.equal('active', true),
          Query.limit(500),
        ],
      ),
      db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: AppConstants.contentTranslationsCollectionId,
        queries: [
          Query.equal('locale', locale),
          Query.equal('content_type', 'department'),
          Query.select(['title', 'description', 'department_ref.\$id']),
          Query.limit(500),
        ],
      ),
    ]);

    return mergeTranslations(
      results[0].rows.map((row) => row.data),
      results[1].rows.map((row) => row.data),
    );
  }

  /// Builds models from `departments` rows, taking the name and description
  /// from a matching translation when one exists. Sorted by displayed name.
  static List<DepartmentModel> mergeTranslations(
    Iterable<Map<String, dynamic>> departments,
    Iterable<Map<String, dynamic>> translations,
  ) {
    final byDepartmentId = <String, Map<String, dynamic>>{};
    for (final translation in translations) {
      final ref = translation['department_ref'];
      if (ref is Map && ref['\$id'] != null) {
        byDepartmentId[ref['\$id'].toString()] = translation;
      }
    }

    return departments.map((dept) {
      final translation = byDepartmentId[(dept['\$id'] ?? '').toString()];
      return translation == null
          ? DepartmentModel.fromMap(dept)
          : DepartmentModel.fromTranslationMap({
              ...translation,
              'department_ref': dept,
            });
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<DepartmentModel?> getDepartmentById(String id, {String locale = 'en'}) async {
    try {
      final results = await Future.wait([
        db.getRow(
          databaseId: AppConstants.databaseId,
          tableId: collectionId,
          rowId: id,
        ),
        db.listRows(
          databaseId: AppConstants.databaseId,
          tableId: AppConstants.contentTranslationsCollectionId,
          queries: [
            Query.equal('department_ref', id),
            Query.equal('locale', locale),
            Query.equal('content_type', 'department'),
            Query.select(['title', 'description', 'department_ref.\$id']),
            Query.limit(1),
          ],
        ),
      ]);
      final dept = results[0] as models.Row;
      final translations = results[1] as models.RowList;
      return mergeTranslations(
        [dept.data],
        translations.rows.map((row) => row.data),
      ).single;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getDepartmentSocials(
    String departmentId,
  ) async {
    // Collection name assumed to be 'department_socials' per spec
      final docs = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: 'department_socials',
      queries: [
        Query.select(['platform', 'url']),
        Query.equal('department_id', departmentId),
        Query.limit(10),
      ],
    );
    return docs.rows.map((doc) => doc.data).toList();
  }
}
