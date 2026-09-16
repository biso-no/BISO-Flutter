import 'package:biso/data/models/app_config.dart';
import 'package:biso/data/models/expense_model.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/expense_service_v2.dart';
import 'package:biso/presentation/screens/expense/create_expense_screen.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/config/app_config_provider.dart';
import 'package:biso/providers/expense/expense_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

const _user = UserModel(
  id: 'u1',
  name: 'Kari Nordmann',
  email: 'kari@bi.no',
  campusId: 'c1',
);

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth() : super(const AuthState(isAuthenticated: true, user: _user));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Offline lookups, as in create_expense_design_test.dart: `_loadLookups`
/// runs from `initState` whatever the screen is showing.
class _FakeExpenseService extends ExpenseServiceV2 {
  @override
  Future<List<Map<String, dynamic>>> listCampuses() async => const [
    {'\$id': 'c1', 'name': 'Oslo'},
  ];

  @override
  Future<List<Map<String, dynamic>>> listDepartmentsForCampus(
    String campusId,
  ) async => const [
    {'Id': 'd1', 'Name': 'Marketing'},
  ];
}

List<Override> _overrides() => [
  authStateProvider.overrideWith((_) => _Auth()),
  expenseServiceProvider.overrideWithValue(_FakeExpenseService()),
  appConfigProvider.overrideWith(
    (_) async => const AppConfig(expensesEnabled: true),
  ),
];

void main() {
  testWidgets('a share the app could not accept is shown, not swallowed', (
    tester,
  ) async {
    // What `ExpenseIntakeService` hands the route when a share held nothing
    // it could take. Before this, the same case only reached `logPrint`:
    // the student was told "Receipt added" by the share sheet and then found
    // an empty reimbursement, with no idea why.
    await pumpBisoScreen(
      tester,
      const CreateExpenseScreen(
        intakeError:
            'BISO could not add those files. Receipts must be PDF, PNG or '
            'JPEG files of 10 MB or less.',
      ),
      overrides: _overrides(),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Receipts must be PDF, PNG or JPEG'),
      findsOneWidget,
    );
  });

  // go_router keeps this page's State for every /explore/expenses/new URL,
  // so a share refused while the form is already open does not build a new
  // screen — it arrives as new arguments to the one on display.
  testWidgets('a refusal that arrives while the form is open is shown', (
    tester,
  ) async {
    final overrides = _overrides();
    await pumpBisoScreen(
      tester,
      const CreateExpenseScreen(),
      overrides: overrides,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining(_refusal), findsNothing);

    await pumpBisoScreen(
      tester,
      const CreateExpenseScreen(intakeError: _refusal, intakeErrorId: '1'),
      overrides: overrides,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(_refusal), findsOneWidget);
  });

  testWidgets('the same refusal twice is shown twice, on the tab that shows '
      'it', (tester) async {
    final overrides = _overrides();
    // A draft with its cost allocation settled opens the receipts/report
    // split, on the Receipts tab — which does not show errors.
    final draft = ExpenseModel(
      id: 'draft-1',
      userId: 'u1',
      campus: 'c1',
      department: 'd1',
      bankAccount: '',
      total: 0,
      status: 'draft',
    );
    await pumpBisoScreen(
      tester,
      CreateExpenseScreen(draftExpense: draft),
      overrides: overrides,
    );
    await tester.pumpAndSettle();
    expect(find.text('Receipt wallet'), findsOneWidget);

    await pumpBisoScreen(
      tester,
      CreateExpenseScreen(
        draftExpense: draft,
        intakeError: _refusal,
        intakeErrorId: '1',
      ),
      overrides: overrides,
    );
    await tester.pumpAndSettle();
    final shown = find.textContaining(_refusal, skipOffstage: false);
    expect(shown, findsOneWidget);
    await tester.ensureVisible(shown);
    expect(find.textContaining(_refusal), findsOneWidget);

    final dismiss = find.widgetWithText(TextButton, 'Dismiss');
    await tester.ensureVisible(dismiss);
    await tester.tap(dismiss);
    await tester.pumpAndSettle();
    expect(find.textContaining(_refusal, skipOffstage: false), findsNothing);

    // The student shares another HEIC: same words, new refusal.
    await pumpBisoScreen(
      tester,
      CreateExpenseScreen(
        draftExpense: draft,
        intakeError: _refusal,
        intakeErrorId: '2',
      ),
      overrides: overrides,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(_refusal, skipOffstage: false), findsOneWidget);
  });
}

const _refusal =
    'BISO could not add those files. Receipts must be PDF, PNG or JPEG '
    'files of 10 MB or less.';
