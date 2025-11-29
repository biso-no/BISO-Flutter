import '../../core/constants/app_constants.dart';
import 'appwrite_service.dart';

class FeatureFlagService {
  Future<bool> isEnabled(String key) async {
    try {
      final doc = await db.getRow(
        databaseId: AppConstants.databaseId,
        tableId: AppConstants.featureFlagsCollectionId,
        rowId: key,
      );
      final data = doc.data;
      final value = data['enabled'];
      if (value is bool) return value;
      if (value is String) return value.toLowerCase() == 'true';
      if (value is num) return value != 0;
      return false;
    } catch (_) {
      return false;
    }
  }
}


