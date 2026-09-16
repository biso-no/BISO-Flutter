import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/expense_model.dart';
import '../../data/services/expense_api_client.dart';
import '../../data/services/expense_service_v2.dart';
import '../../core/logging/print_migration.dart';

// Service provider
final expenseServiceProvider = Provider<ExpenseServiceV2>(
  (ref) => ExpenseServiceV2(),
);

/// Injectable so screen tests can replace the HTTP-backed client with a
/// fake, the same way [expenseServiceProvider] lets them fake the
/// Appwrite-backed service.
final expenseApiClientProvider = Provider<ExpenseApiClient>(
  (ref) => ExpenseApiClient(),
);

// Expenses state provider
final expensesStateProvider =
    StateNotifierProvider<ExpensesNotifier, ExpensesState>((ref) {
      return ExpensesNotifier(
        ref.watch(expenseServiceProvider),
        ref.watch(expenseApiClientProvider),
      );
    });

// Filtered expenses provider
final filteredExpensesProvider = Provider.family<List<ExpenseModel>, String>((
  ref,
  status,
) {
  final expensesState = ref.watch(expensesStateProvider);
  if (status == 'all') {
    return expensesState.expenses;
  }
  return expensesState.expenses
      .where((expense) => expense.status == status)
      .toList();
});

// Expense statistics provider
final expenseStatisticsProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  final service = ref.watch(expenseServiceProvider);
  return service.getExpenseStatistics();
});

class ExpensesState {
  final List<ExpenseModel> expenses;
  final bool isLoading;
  final String? error;
  final ExpenseModel? selectedExpense;

  const ExpensesState({
    this.expenses = const [],
    this.isLoading = false,
    this.error,
    this.selectedExpense,
  });

  ExpensesState copyWith({
    List<ExpenseModel>? expenses,
    bool? isLoading,
    String? error,
    ExpenseModel? selectedExpense,
  }) {
    return ExpensesState(
      expenses: expenses ?? this.expenses,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      selectedExpense: selectedExpense ?? this.selectedExpense,
    );
  }

  // Calculate totals by status
  double get totalDraftAmount =>
      expenses.where((e) => e.isDraft).fold(0.0, (sum, e) => sum + e.total);

  double get totalPendingAmount =>
      expenses.where((e) => e.isPending).fold(0.0, (sum, e) => sum + e.total);

  double get totalSubmittedAmount => expenses
      .where((e) => e.isSubmitted)
      .fold(0.0, (sum, e) => sum + e.total);

  double get totalSuccessAmount =>
      expenses.where((e) => e.isSuccess).fold(0.0, (sum, e) => sum + e.total);

  double get totalRejectedAmount =>
      expenses.where((e) => e.isRejected).fold(0.0, (sum, e) => sum + e.total);

  // Count by status
  int get draftCount => expenses.where((e) => e.isDraft).length;
  int get pendingCount => expenses.where((e) => e.isPending).length;
  int get submittedCount => expenses.where((e) => e.isSubmitted).length;
  int get successCount => expenses.where((e) => e.isSuccess).length;
  int get rejectedCount => expenses.where((e) => e.isRejected).length;
}

class ExpensesNotifier extends StateNotifier<ExpensesState> {
  final ExpenseServiceV2 _service;
  final ExpenseApiClient _api;

  ExpensesNotifier(this._service, this._api) : super(const ExpensesState()) {
    loadUserExpenses();
  }

  /// Load user expenses
  Future<void> loadUserExpenses({String? userId}) async {
    try {
      logPrint('💰 ExpensesNotifier: Loading user expenses');
      state = state.copyWith(isLoading: true, error: null);

      final expenses = await _service.getUserExpenses(userId: userId);

      logPrint('💰 ExpensesNotifier: Loaded ${expenses.length} expenses');
      state = state.copyWith(expenses: expenses, isLoading: false, error: null);
    } catch (e) {
      logPrint('💰 ExpensesNotifier: Failed to load expenses: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load expenses: $e',
      );
    }
  }

  /// Load expenses filtered by status
  Future<void> loadExpensesByStatus(String status, {String? userId}) async {
    try {
      logPrint('💰 ExpensesNotifier: Loading expenses with status: $status');
      state = state.copyWith(isLoading: true, error: null);

      final expenses = await _service.getExpensesByStatus(
        status,
        userId: userId,
      );

      state = state.copyWith(expenses: expenses, isLoading: false, error: null);
    } catch (e) {
      logPrint('💰 ExpensesNotifier: Failed to load expenses by status: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load expenses: $e',
      );
    }
  }

  /// Load a specific expense
  Future<void> loadExpense(String expenseId) async {
    try {
      logPrint('💰 ExpensesNotifier: Loading expense $expenseId');

      final expense = await _service.getExpense(expenseId);

      if (expense != null) {
        state = state.copyWith(selectedExpense: expense);

        // Also update the expense in the list if it exists
        final updatedExpenses = state.expenses.map((e) {
          return e.id == expenseId ? expense : e;
        }).toList();

        state = state.copyWith(expenses: updatedExpenses);
      }
    } catch (e) {
      logPrint('💰 ExpensesNotifier: Failed to load expense: $e');
      state = state.copyWith(error: 'Failed to load expense: $e');
    }
  }

  /// Delete an expense
  Future<bool> deleteExpense(String expenseId) async {
    try {
      logPrint('💰 ExpensesNotifier: Deleting expense $expenseId');
      state = state.copyWith(isLoading: true, error: null);

      // Students have no delete grant on expense rows; the API checks the
      // draft is theirs and still a draft before deleting it.
      await _api.deleteDraft(expenseId);

      // Remove from the list
      final updatedExpenses = state.expenses
          .where((e) => e.id != expenseId)
          .toList();

      state = state.copyWith(
        expenses: updatedExpenses,
        selectedExpense: state.selectedExpense?.id == expenseId
            ? null
            : state.selectedExpense,
        isLoading: false,
        error: null,
      );

      logPrint('💰 ExpensesNotifier: Deleted expense $expenseId');
      return true;
    } catch (e) {
      logPrint('💰 ExpensesNotifier: Failed to delete expense: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to delete expense: $e',
      );
      return false;
    }
  }

  /// Refresh expenses
  Future<void> refresh() async {
    await loadUserExpenses();
  }

  /// Clear selected expense
  void clearSelectedExpense() {
    state = state.copyWith(selectedExpense: null);
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }
}
