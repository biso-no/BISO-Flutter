import 'package:biso/data/models/app_config.dart';
import 'package:biso/data/models/expense_model.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/expense_service_v2.dart';
import 'package:biso/presentation/screens/expense/create_expense_screen.dart';
import 'package:biso/presentation/screens/explore/expenses_screen.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/config/app_config_provider.dart';
import 'package:biso/providers/expense/expense_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

const _user = UserModel(id: 'u1', name: 'Test Student', email: 'student@bi.no');

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth() : super(const AuthState(isAuthenticated: true, user: _user));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Never touches Appwrite: even with reimbursements switched off, both
/// screens read from `ExpenseServiceV2` during the one frame before
/// `appConfigProvider` resolves — `ExpensesNotifier.loadUserExpenses` runs
/// from its constructor, and `CreateExpenseScreen._loadLookups` runs from
/// `initState`'s post-frame callback regardless of what `build` returns — so
/// a real `ExpenseServiceV2` would try a network call and hang the test,
/// mirroring the fakes in expenses_design_test.dart /
/// create_expense_design_test.dart.
class _FakeExpenseService extends ExpenseServiceV2 {
  @override
  Future<List<ExpenseModel>> getUserExpenses({
    String? userId,
    List<String> queries = const [],
  }) async => const [];

  @override
  Future<List<Map<String, dynamic>>> listCampuses() async => const [];
}

List<Override> _switchedOff() => [
  authStateProvider.overrideWith((_) => _Auth()),
  appConfigProvider.overrideWith(
    (_) async => const AppConfig(expensesEnabled: false),
  ),
  expenseServiceProvider.overrideWithValue(_FakeExpenseService()),
];

void main() {
  testWidgets(
    'the expenses list says reimbursements are off instead of loading',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const ExpensesScreen(),
        overrides: _switchedOff(),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Reimbursements are currently unavailable'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a deep link to a new expense also lands on the unavailable page',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const CreateExpenseScreen(),
        overrides: _switchedOff(),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Reimbursements are currently unavailable'),
        findsOneWidget,
      );
    },
  );
}
