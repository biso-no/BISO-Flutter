import 'package:appwrite/appwrite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logging/print_migration.dart';
import '../models/expense_model.dart';
import 'appwrite_service.dart';

class ExpenseServiceV2 {
  static const String expensesCollectionId = AppConstants.expensesCollectionId;
  static const String attachmentsCollectionId =
      AppConstants.expenseAttachmentsCollectionId;

  /// Get all expenses for the current user
  /// Note: Due to Appwrite relationship query limitations, we fetch expenses first
  /// and let Appwrite include relationship data automatically
  Future<List<ExpenseModel>> getUserExpenses({
    String? userId,
    List<String> queries = const [],
  }) async {
    try {
      logPrint('💰 ExpenseServiceV2: Fetching user expenses');
      // Resolve userId: prefer provided, otherwise use the currently authenticated user
      String? effectiveUserId = userId;
      if (effectiveUserId == null || effectiveUserId.isEmpty) {
        try {
          final user = await account.get();
          effectiveUserId = user.$id;
        } catch (_) {
          // If we cannot resolve current user, we proceed without user filter
        }
      }

      // Build queries: always order by creation date desc, filter by user when available,
      // and include any additional queries passed in (status, campus, department, etc.)
      final List<String> mergedQueries = <String>[];
      if (effectiveUserId != null && effectiveUserId.isNotEmpty) {
        mergedQueries.add(Query.equal('userId', effectiveUserId));
      }
      mergedQueries.addAll(queries);
      mergedQueries.add(Query.orderDesc('\$createdAt'));

      final documents = await db.listRows(
        databaseId: AppConstants.databaseId,
        tableId: expensesCollectionId,
        queries: mergedQueries,
      );

      logPrint('💰 ExpenseServiceV2: Found ${documents.total} expenses');

      final expenses = <ExpenseModel>[];
      for (final doc in documents.rows) {
        try {
          // Appwrite should automatically include relationship data
          // If expenseAttachments relationship is properly configured
          final expense = ExpenseModel.fromMap(doc.data);
          expenses.add(expense);
        } catch (e) {
          logPrint(
            '💰 ExpenseServiceV2: Failed to parse expense ${doc.data['\$id']}: $e',
          );
          logPrint(
            '💰 ExpenseServiceV2: Document data: ${doc.data.toString()}',
          );
          // Continue with other expenses instead of failing completely
        }
      }

      return expenses;
    } catch (e) {
      logPrint('💰 ExpenseServiceV2: Failed to fetch user expenses: $e');
      throw Exception('Failed to fetch expenses: $e');
    }
  }

  /// Get a specific expense by ID
  Future<ExpenseModel?> getExpense(String expenseId) async {
    try {
      logPrint('💰 ExpenseServiceV2: Fetching expense $expenseId');

      final doc = await db.getRow(
        databaseId: AppConstants.databaseId,
        tableId: expensesCollectionId,
        rowId: expenseId,
      );

      // Appwrite should automatically include relationship data
      return ExpenseModel.fromMap(doc.data);
    } catch (e) {
      logPrint('💰 ExpenseServiceV2: Failed to fetch expense $expenseId: $e');
      return null;
    }
  }

  /// Get expenses filtered by status
  Future<List<ExpenseModel>> getExpensesByStatus(
    String status, {
    String? userId,
  }) async {
    return getUserExpenses(
      userId: userId,
      queries: [Query.equal('status', status)],
    );
  }

  /// Get expenses filtered by campus
  Future<List<ExpenseModel>> getExpensesByCampus(
    String campus, {
    String? userId,
  }) async {
    return getUserExpenses(
      userId: userId,
      queries: [Query.equal('campus', campus)],
    );
  }

  /// Get expenses filtered by department
  Future<List<ExpenseModel>> getExpensesByDepartment(
    String department, {
    String? userId,
  }) async {
    return getUserExpenses(
      userId: userId,
      queries: [Query.equal('department', department)],
    );
  }

  /// Get expense statistics for the current user
  Future<Map<String, dynamic>> getExpenseStatistics({String? userId}) async {
    try {
      final expenses = await getUserExpenses(userId: userId);

      final stats = <String, dynamic>{
        'total_count': expenses.length,
        'total_amount': 0.0,
        'draft_count': 0,
        'draft_amount': 0.0,
        'pending_count': 0,
        'pending_amount': 0.0,
        'submitted_count': 0,
        'submitted_amount': 0.0,
        'success_count': 0,
        'success_amount': 0.0,
        'rejected_count': 0,
        'rejected_amount': 0.0,
        'prepayment_count': 0,
        'prepayment_amount': 0.0,
      };

      for (final expense in expenses) {
        stats['total_amount'] += expense.total;

        switch (expense.status) {
          case 'draft':
            stats['draft_count']++;
            stats['draft_amount'] += expense.total;
            break;
          case 'pending':
            stats['pending_count']++;
            stats['pending_amount'] += expense.total;
            break;
          case 'submitted':
            stats['submitted_count']++;
            stats['submitted_amount'] += expense.total;
            break;
          case 'success':
            stats['success_count']++;
            stats['success_amount'] += expense.total;
            break;
          case 'rejected':
            stats['rejected_count']++;
            stats['rejected_amount'] += expense.total;
            break;
        }

        if (expense.hasPrepayment) {
          stats['prepayment_count']++;
          stats['prepayment_amount'] += expense.prepaymentAmount ?? 0.0;
        }
      }

      return stats;
    } catch (e) {
      logPrint('💰 ExpenseServiceV2: Failed to get statistics: $e');
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> listDepartmentsForCampus(
    String campusId,
  ) async {
    final results = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: AppConstants.departmentsCollectionId,
      queries: [
        Query.equal('campus_id', campusId),
        Query.orderAsc('Name'),
        Query.limit(100),
      ],
    );
    return results.rows.map((doc) => doc.data).toList();
  }

  Future<List<Map<String, dynamic>>> listCampuses() async {
    final results = await db.listRows(
      databaseId: AppConstants.databaseId,
      tableId: AppConstants.campusesCollectionId,
      queries: [
        Query.select(['\$id', 'name']),
        Query.orderAsc('name'),
        Query.limit(100),
      ],
    );
    return results.rows.map((doc) => doc.data).toList();
  }
}
