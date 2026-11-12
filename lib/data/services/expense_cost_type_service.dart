import 'package:appwrite/appwrite.dart';

import '../../core/constants/app_constants.dart';
import '../models/expense_cost_type_option.dart';
import 'appwrite_service.dart' as appwrite;

/// Reads the expense types students can choose from. The table is readable by
/// anyone, so no session is needed.
class ExpenseCostTypeService {
  ExpenseCostTypeService({TablesDB? tablesDb}) : _db = tablesDb ?? appwrite.db;

  final TablesDB _db;

  Future<List<ExpenseCostTypeOption>> listActive() async {
    final result = await _db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: AppConstants.expenseCostTypesTableId,
      queries: [Query.orderAsc('sort_order'), Query.limit(100)],
    );
    // Only an explicit false hides a type; a missing value counts as active,
    // like on the server.
    return result.rows
        .where((row) => row.data['active'] != false)
        .map((row) => ExpenseCostTypeOption.fromRow(row.data))
        .toList();
  }
}
