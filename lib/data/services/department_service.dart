import 'package:appwrite/appwrite.dart';

import '../../core/constants/app_constants.dart';
import '../models/department_model.dart';
import '../services/appwrite_service.dart';

class DepartmentService {
  static const String collectionId = AppConstants.departmentsCollectionId;

  Future<List<DepartmentModel>> getActiveDepartmentsForCampus(
    String campusId, {
    String locale = 'en',
  }) async {
    final docs = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: AppConstants.contentTranslationsCollectionId,
      queries: [
        Query.equal('locale', locale),
        Query.equal('content_type', 'department'),
        Query.select(['*', 'department_ref.*']),
        Query.limit(200),
      ],
    );
    
    return docs.rows
        .where((doc) {
          final dept = doc.data['department_ref'];
          return dept != null &&
              dept['campus_id'] == campusId &&
              (dept['active'] == true || dept['active'].toString() == 'true');
        })
        .map((doc) => DepartmentModel.fromTranslationMap(doc.data))
        .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<DepartmentModel?> getDepartmentById(String id, {String locale = 'en'}) async {
    try {
      final docs = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: AppConstants.contentTranslationsCollectionId,
        queries: [
          Query.equal('department_ref', id),
          Query.equal('locale', locale),
          Query.equal('content_type', 'department'),
          Query.select(['*', 'department_ref.*']),
          Query.limit(1),
        ],
      );
      if (docs.rows.isEmpty) return null;
      return DepartmentModel.fromTranslationMap(docs.rows.first.data);
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
