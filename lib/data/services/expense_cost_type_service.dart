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
      queries: [
        Query.equal('active', true),
        Query.orderAsc('sort_order'),
        Query.limit(100),
      ],
    );
    return result.rows
        .map((row) => ExpenseCostTypeOption.fromRow(row.data))
        .toList();
  }
}
