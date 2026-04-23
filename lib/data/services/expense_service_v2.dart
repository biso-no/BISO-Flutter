import 'dart:io';
import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as aw_models;
import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../../core/logging/print_migration.dart';
import '../models/expense_model.dart';
import '../models/expense_attachment_model.dart';
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
          logPrint('💰 ExpenseServiceV2: Document data: ${doc.data.toString()}');
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

  /// Create a new expense with attachments
  Future<ExpenseModel> createExpense({
    required String campus,
    required String department,
    required String bankAccount,
    String? description,
    required double total,
    double? prepaymentAmount,
    String status = 'pending',
    String? eventName,
    List<ExpenseAttachmentModel> attachments = const [],
  }) async {
    try {
      logPrint('💰 ExpenseServiceV2: Creating new expense');

      // Get current user
      final user = await account.get();

      // Step 1: Create attachment documents first
      final createdAttachmentIds = <String>[];
      for (final attachment in attachments) {
        try {
          final attachmentData = attachment.toMap();

          final attachmentDoc =
              await db.createRow(
                databaseId: AppConstants.databaseId,
                tableId: attachmentsCollectionId,
                rowId: ID.unique(),
                data: attachmentData,
              );

          if (attachmentDoc.data['\$id'] != null) {
            createdAttachmentIds.add(attachmentDoc.data['\$id']);
          }
        } catch (e) {
          logPrint('💰 ExpenseServiceV2: Failed to create attachment: $e');
          // Continue with other attachments
        }
      }

      // Step 2: Create the expense document with attachment relationships
      final expenseData = {
        'userId': user.$id,
        'campus': campus,
        'department': department,
        'bank_account': bankAccount,
        if (description != null) 'description': description,
        'total': total,
        if (prepaymentAmount != null) 'prepayment_amount': prepaymentAmount,
        'status': status,
        if (eventName != null) 'eventName': eventName,
        if (createdAttachmentIds.isNotEmpty)
          'expenseAttachments': createdAttachmentIds,
      };

      final doc = await db.createRow(
        databaseId: AppConstants.databaseId,
        tableId: expensesCollectionId,
        rowId: ID.unique(),
        data: expenseData,
      );

      final expenseId = doc.data['\$id'];
      logPrint(
        '💰 ExpenseServiceV2: Created expense $expenseId with ${createdAttachmentIds.length} attachments',
      );

      return ExpenseModel.fromMap(doc.data);
    } catch (e) {
      logPrint('💰 ExpenseServiceV2: Failed to create expense: $e');
      throw Exception('Failed to create expense: $e');
    }
  }

  /// Update an existing expense
  Future<ExpenseModel> updateExpense({
    required String expenseId,
    String? campus,
    String? department,
    String? bankAccount,
    String? description,
    double? total,
    double? prepaymentAmount,
    String? status,
    String? eventName,
  }) async {
    try {
      logPrint('💰 ExpenseServiceV2: Updating expense $expenseId');

      final updateData = <String, dynamic>{};
      if (campus != null) updateData['campus'] = campus;
      if (department != null) updateData['department'] = department;
      if (bankAccount != null) updateData['bank_account'] = bankAccount;
      if (description != null) updateData['description'] = description;
      if (total != null) updateData['total'] = total;
      if (prepaymentAmount != null) updateData['prepayment_amount'] = prepaymentAmount;
      if (status != null) updateData['status'] = status;
      if (eventName != null) updateData['eventName'] = eventName;

      final doc = await db.updateRow(
        databaseId: AppConstants.databaseId,
        tableId: expensesCollectionId,
        rowId: expenseId,
        data: updateData,
      );

      return ExpenseModel.fromMap(doc.data);
    } catch (e) {
      logPrint('💰 ExpenseServiceV2: Failed to update expense $expenseId: $e');
      throw Exception('Failed to update expense: $e');
    }
  }

  /// Delete an expense and its attachments
  Future<void> deleteExpense(String expenseId) async {
    try {
      logPrint('💰 ExpenseServiceV2: Deleting expense $expenseId');

      // Get the expense first to see what attachments are linked
      final expense = await getExpense(expenseId);
      if (expense != null && expense.expenseAttachments.isNotEmpty) {
        // Delete all linked attachments
        for (final attachment in expense.expenseAttachments) {
          if (attachment.id != null) {
            try {
              await db.deleteRow(
                databaseId: AppConstants.databaseId,
                tableId: attachmentsCollectionId,
                rowId: attachment.id!,
              );
            } catch (e) {
              logPrint(
                '💰 ExpenseServiceV2: Failed to delete attachment ${attachment.id}: $e',
              );
              // Continue with other attachments
            }
          }
        }
      }

      // Delete the expense document
      await db.deleteRow(
        databaseId: AppConstants.databaseId,
        tableId: expensesCollectionId,
        rowId: expenseId,
      );

      logPrint('💰 ExpenseServiceV2: Successfully deleted expense $expenseId');
    } catch (e) {
      logPrint('💰 ExpenseServiceV2: Failed to delete expense $expenseId: $e');
      throw Exception('Failed to delete expense: $e');
    }
  }

  /// Add attachment to an existing expense
  Future<ExpenseAttachmentModel> addExpenseAttachment({
    required String expenseId,
    required String type,
    DateTime? date,
    String? url,
    double? amount,
    String? description,
  }) async {
    try {
      logPrint('💰 ExpenseServiceV2: Adding attachment to expense $expenseId');

      // Step 1: Create the attachment document
      final attachmentData = {
        'type': type,
        if (date != null) 'date': date.toIso8601String(),
        if (url != null) 'url': url,
        if (amount != null) 'amount': amount,
        if (description != null) 'description': description,
      };

      final attachmentDoc = await db.createRow(
        databaseId: AppConstants.databaseId,
        tableId: attachmentsCollectionId,
        rowId: ID.unique(),
        data: attachmentData,
      );

      final attachmentId = attachmentDoc.data['\$id'];

      // Step 2: Get current expense to update its attachments relationship
      final currentExpense = await getExpense(expenseId);
      if (currentExpense != null) {
        final currentAttachmentIds = currentExpense.expenseAttachments
            .where((a) => a.id != null)
            .map((a) => a.id!)
            .toList();

        // Add the new attachment ID
        currentAttachmentIds.add(attachmentId);

        // Update the expense with the new attachment relationship
        await db.updateRow(
          databaseId: AppConstants.databaseId,
          tableId: expensesCollectionId,
          rowId: expenseId,
          data: {'expenseAttachments': currentAttachmentIds},
        );
      }

      return ExpenseAttachmentModel.fromMap(attachmentDoc.data);
    } catch (e) {
      logPrint('💰 ExpenseServiceV2: Failed to add attachment: $e');
      throw Exception('Failed to add attachment: $e');
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

  // MARK: - Existing methods for file upload and AI functionality

  Future<Map<String, dynamic>> createExpenseDocument({
    required Map<String, dynamic> data,
  }) async {
    final map = await db.createRow(
      databaseId: AppConstants.databaseId,
      tableId: expensesCollectionId,
      rowId: ID.unique(),
      data: data,
    );
    return map.data;
  }

  Future<String> uploadAttachmentFile(File file) async {
    final aw_models.File created = await storage.createFile(
      bucketId: AppConstants.expensesBucketId,
      fileId: ID.unique(),
      file: InputFile.fromPath(path: file.path),
    );
    return _publicFileUrl(AppConstants.expensesBucketId, created.$id);
  }

  Future<Map<String, dynamic>> createAttachmentDocument({
    required DateTime date,
    required String url,
    required double amount,
    required String description,
    required String type,
  }) async {
    final map = await db.createRow(
      databaseId: AppConstants.databaseId,
      tableId: attachmentsCollectionId,
      rowId: ID.unique(),
      data: {
        'date': date.toIso8601String(),
        'url': url,
        'amount': amount,
        'description': description,
        'type': type,
      },
    );
    return map.data;
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

  Future<Map<String, dynamic>> analyzeReceiptText(String ocrText) async {
    final endpoint = client.endPoint;
    final projectId = client.config['project'];
    final jwt = await account.createJWT();
    final url =
        '$endpoint/functions/${AppConstants.fnParseReceiptId}/executions';
    final res = await http.post(
      Uri.parse(url),
      headers: {
        'content-type': 'application/json',
        'X-Appwrite-Project': projectId ?? '',
        'X-Appwrite-JWT': jwt.jwt,
      },
      body: jsonEncode({'body': ocrText}),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final response = (data['response'] ?? '') as String;
      if (response.isEmpty) return <String, dynamic>{};
      try {
        return jsonDecode(response) as Map<String, dynamic>;
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    return <String, dynamic>{};
  }

  Future<String> summarizeExpenseDescriptions(List<String> descriptions) async {
    final endpoint = client.endPoint;
    final projectId = client.config['project'];
    final jwt = await account.createJWT();
    final url =
        '$endpoint/functions/${AppConstants.fnSummarizeExpenseId}/executions';
    final payload = {'descriptions': descriptions};
    final res = await http.post(
      Uri.parse(url),
      headers: {
        'content-type': 'application/json',
        'X-Appwrite-Project': projectId ?? '',
        'X-Appwrite-JWT': jwt.jwt,
      },
      body: jsonEncode({'body': jsonEncode(payload)}),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final response = (data['response'] ?? '') as String;
      return response;
    }
    return '';
  }

  String _publicFileUrl(String bucketId, String fileId) {
    final endpoint = client.endPoint;
    final projectId = client.config['project'];
    return '$endpoint/storage/buckets/$bucketId/files/$fileId/view?project=$projectId';
  }
}
