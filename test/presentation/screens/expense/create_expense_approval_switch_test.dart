import 'package:biso/data/models/app_config.dart';
import 'package:biso/data/models/expense_attachment_model.dart';
import 'package:biso/data/models/expense_model.dart';
import 'package:biso/data/models/expense_v2_models.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/models/expense_cost_type_option.dart';
import 'package:biso/data/services/expense_api_client.dart';
import 'package:biso/data/services/expense_cost_type_service.dart';
import 'package:biso/data/services/expense_service_v2.dart';
import 'package:biso/presentation/screens/expense/create_expense_screen.dart';
import 'package:biso/presentation/screens/expense/widgets/approval_switch_card.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/config/app_config_provider.dart';
import 'package:biso/providers/expense/expense_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

/// The approval switch card on the report tab: one card at most, picked from
/// the department, and only the shown switch is ever sent.

const _user = UserModel(
  id: 'u1',
  name: 'Kari Nordmann',
  email: 'kari@bi.no',
  phone: '+4791234567',
  address: 'Nydalsveien 37',
  zipCode: '0484',
  city: 'Oslo',
  campusId: '1',
  bankAccount: '86011117947',
);

class _Auth extends Notifier<AuthState> implements AuthNotifier {
  @override
  AuthState build() => const AuthState(isAuthenticated: true, user: _user);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeExpenseService extends ExpenseServiceV2 {
  @override
  Future<List<ExpenseModel>> getUserExpenses({
    String? userId,
    List<String> queries = const [],
  }) async => const [];

  @override
  Future<List<Map<String, dynamic>>> listCampuses() async => const [
    {'\$id': '1', 'name': 'Oslo'},
    {'\$id': '2', 'name': 'Bergen'},
  ];

  @override
  Future<List<Map<String, dynamic>>> listDepartmentsForCampus(
    String campusId,
  ) async => const [
    {'Id': '500', 'Name': 'Marketing'},
    {'Id': '2', 'Name': 'Ledelsen'},
    {'Id': '302', 'Name': 'Events'},
  ];
}

class _Types extends ExpenseCostTypeService {
  @override
  Future<List<ExpenseCostTypeOption>> listActive() async => const [
    ExpenseCostTypeOption(slug: 'food', label: 'Food'),
  ];
}

class _RecordingApi extends ExpenseApiClient {
  final List<Map<String, dynamic>> drafts = [];

  @override
  Future<String> summarize({
    required ExpenseAssignment assignment,
    required List<ExpenseReceiptDraft> receipts,
  }) async => '';

  @override
  Future<ExpenseDraftResult> saveDraft(Map<String, dynamic> payload) async {
    drafts.add(payload);
    return const ExpenseDraftResult(success: true, draftId: 'draft-1');
  }
}

ExpenseModel _draft({
  required String campus,
  required String department,
  bool manager = false,
  bool controller = false,
}) => ExpenseModel(
  id: 'draft-1',
  userId: 'u1',
  campus: campus,
  department: department,
  departmentName: department.isEmpty ? '' : 'Dept',
  bankAccount: '86011117947',
  description: 'Trip',
  total: 120,
  status: 'draft',
  submitterIsFinancialManager: manager,
  submitterIsController: controller,
  expenseAttachments: const [
    ExpenseAttachmentModel(
      id: 'a1',
      url: 'file1',
      amount: 120,
      description: 'Lunch',
      type: 'image/jpeg',
      costType: 'food',
    ),
  ],
);

List<Override> _overrides(_RecordingApi api) => [
  expenseCostTypeServiceProvider.overrideWithValue(_Types()),
  authStateProvider.overrideWith(() => _Auth()),
  expenseServiceProvider.overrideWithValue(_FakeExpenseService()),
  expenseApiClientProvider.overrideWithValue(api),
  appConfigProvider.overrideWith(
    (_) async => const AppConfig(expensesEnabled: true),
  ),
];

Future<_RecordingApi> _pump(WidgetTester tester, ExpenseModel draft) async {
  final api = _RecordingApi();
  await pumpBisoScreen(
    tester,
    CreateExpenseScreen(draftExpense: draft),
    overrides: _overrides(api),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Report'));
  await tester.pumpAndSettle();
  return api;
}

Future<Map<String, dynamic>> _saveDraft(
  WidgetTester tester,
  _RecordingApi api,
) async {
  await tester.tap(find.widgetWithText(OutlinedButton, 'Update draft'));
  await tester.pumpAndSettle();
  return api.drafts.last;
}

void main() {
  testWidgets('only one card is shown', (tester) async {
    await _pump(tester, _draft(campus: '1', department: '500'));
    expect(find.byType(ApprovalSwitchCard), findsOneWidget);
    expect(
      find.text("I'm this department's financial manager"),
      findsOneWidget,
    );
    expect(find.text("I'm the campus controller"), findsNothing);
  });

  testWidgets('a leadership department shows the controller card only', (
    tester,
  ) async {
    await _pump(tester, _draft(campus: '1', department: '2'));
    expect(find.byType(ApprovalSwitchCard), findsOneWidget);
    expect(find.text("I'm the campus controller"), findsOneWidget);
    expect(find.text("I'm this department's financial manager"), findsNothing);
  });

  testWidgets('a department without a switch shows no card', (tester) async {
    await _pump(tester, _draft(campus: '2', department: '302'));
    expect(find.byType(ApprovalSwitchCard), findsNothing);
  });

  testWidgets('a hydrated controller flag on an OSL department is dropped', (
    tester,
  ) async {
    final api = await _pump(
      tester,
      _draft(campus: '1', department: '500', controller: true),
    );
    final payload = await _saveDraft(tester, api);
    expect(payload['submitter_is_controller'], false);
    expect(payload['submitter_is_financial_manager'], false);
  });

  testWidgets('a hydrated financial-manager flag on a leadership department '
      'is dropped', (tester) async {
    final api = await _pump(
      tester,
      _draft(campus: '1', department: '2', manager: true),
    );
    final payload = await _saveDraft(tester, api);
    expect(payload['submitter_is_financial_manager'], false);
    expect(payload['submitter_is_controller'], false);
  });

  testWidgets('a hydrated flag that still applies is sent', (tester) async {
    final api = await _pump(
      tester,
      _draft(campus: '1', department: '2', controller: true),
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    final payload = await _saveDraft(tester, api);
    expect(payload['submitter_is_controller'], true);
    expect(payload['submitter_is_financial_manager'], false);
  });

  testWidgets('turning the switch on sends the flag', (tester) async {
    final api = await _pump(tester, _draft(campus: '1', department: '500'));
    // Tall enough for the card to sit inside the viewport.
    tester.view.physicalSize = const Size(1170, 5400);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    final payload = await _saveDraft(tester, api);
    expect(payload['submitter_is_financial_manager'], true);
    expect(payload['submitter_is_controller'], false);
  });

  testWidgets('changing department clears both switches', (tester) async {
    // A draft saved before a department was chosen opens on the gate with
    // its flag; choosing a department starts the switches from off.
    final api = _RecordingApi();
    await pumpBisoScreen(
      tester,
      CreateExpenseScreen(
        draftExpense: _draft(campus: '1', department: '', manager: true),
      ),
      overrides: _overrides(api),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Department'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marketing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    expect(find.byType(ApprovalSwitchCard), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    final payload = await _saveDraft(tester, api);
    expect(payload['submitter_is_financial_manager'], false);
    expect(payload['submitter_is_controller'], false);
  });
}
