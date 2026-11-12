import 'package:biso/data/models/app_config.dart';
import 'package:biso/data/models/expense_attachment_model.dart';
import 'package:biso/data/models/expense_cost_type_option.dart';
import 'package:biso/data/models/expense_model.dart';
import 'package:biso/data/models/expense_v2_models.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/expense_api_client.dart';
import 'package:biso/data/services/expense_cost_type_service.dart';
import 'package:biso/data/services/expense_service_v2.dart';
import 'package:biso/presentation/screens/expense/create_expense_screen.dart';
import 'package:biso/presentation/screens/expense/widgets/receipt_type_chip.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/config/app_config_provider.dart';
import 'package:biso/providers/expense/expense_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

/// The expense types behind a resumed draft: a failed read must never turn
/// stored types into empty ones, and a retry re-checks them.

const _user = UserModel(
  id: 'u1',
  name: 'Kari Nordmann',
  email: 'kari@bi.no',
  phone: '+4791234567',
  address: 'Nydalsveien 37',
  zipCode: '0484',
  city: 'Oslo',
  campusId: 'c1',
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
    {'\$id': 'c1', 'name': 'Oslo'},
  ];

  @override
  Future<List<Map<String, dynamic>>> listDepartmentsForCampus(
    String campusId,
  ) async => const [
    {'Id': 'd1', 'Name': 'Marketing'},
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

/// Fails until [failing] is cleared, then answers [types].
class _FlakyTypes extends ExpenseCostTypeService {
  _FlakyTypes({required this.failing, required this.types});

  bool failing;
  final List<ExpenseCostTypeOption> types;

  @override
  Future<List<ExpenseCostTypeOption>> listActive() async {
    if (failing) throw Exception('offline');
    return types;
  }
}

const _food = ExpenseCostTypeOption(slug: 'food', label: 'Food');

final _draft = ExpenseModel(
  id: 'draft-1',
  userId: 'u1',
  campus: 'c1',
  department: 'd1',
  bankAccount: '86011117947',
  description: 'Trip',
  total: 240,
  status: 'draft',
  expenseAttachments: const [
    ExpenseAttachmentModel(
      id: 'a1',
      url: 'file1',
      amount: 120,
      description: 'Lunch',
      type: 'image/jpeg',
      costType: 'food',
    ),
    ExpenseAttachmentModel(
      id: 'a2',
      url: 'file2',
      amount: 120,
      description: 'Gone',
      type: 'image/jpeg',
      costType: 'retired',
    ),
  ],
);

List<Override> _overrides(_FlakyTypes types, _RecordingApi api) => [
  expenseCostTypeServiceProvider.overrideWithValue(types),
  authStateProvider.overrideWith(() => _Auth()),
  expenseServiceProvider.overrideWithValue(_FakeExpenseService()),
  expenseApiClientProvider.overrideWithValue(api),
  appConfigProvider.overrideWith(
    (_) async => const AppConfig(expensesEnabled: true),
  ),
];

Future<void> _pump(
  WidgetTester tester,
  _FlakyTypes types,
  _RecordingApi api,
) async {
  await pumpBisoScreen(
    tester,
    CreateExpenseScreen(draftExpense: _draft),
    overrides: _overrides(types, api),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Report'));
  await tester.pumpAndSettle();
}

FilledButton _submit(WidgetTester tester) => tester.widget<FilledButton>(
  find.ancestor(
    of: find.text('Submit'),
    matching: find.byWidgetPredicate((w) => w is FilledButton),
  ),
);

void main() {
  testWidgets('a hydrated active slug stays chosen and the chip shows it', (
    tester,
  ) async {
    final api = _RecordingApi();
    await _pump(tester, _FlakyTypes(failing: false, types: const [_food]), api);

    expect(find.text('Couldn\'t load expense types'), findsNothing);
    expect(find.byType(ReceiptTypeChip), findsWidgets);
    // The chosen slug reads as its label; the retired one asks again.
    expect(find.text(_food.label), findsWidgets);
    expect(find.text('Choose a type'), findsWidgets);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Update draft'));
    await tester.pumpAndSettle();
    expect(api.drafts, hasLength(1));
  });

  testWidgets('when the types fail to load the saved draft keeps its slugs and '
      'Submit is disabled', (tester) async {
    final api = _RecordingApi();
    await _pump(tester, _FlakyTypes(failing: true, types: const [_food]), api);

    expect(find.text('Couldn\'t load expense types'), findsOneWidget);
    expect(_submit(tester).onPressed, isNull);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Update draft'));
    await tester.pumpAndSettle();

    final attachments = api.drafts.single['expenseAttachments'] as List;
    expect(attachments.map((a) => a['cost_type']), ['food', 'retired']);
    expect(attachments.every((a) => a['cost_type_chosen'] == true), isTrue);
  });

  testWidgets('Retry loads the types and re-checks the stored slugs', (
    tester,
  ) async {
    final api = _RecordingApi();
    final types = _FlakyTypes(failing: true, types: const [_food]);
    await _pump(tester, types, api);
    expect(find.text('Couldn\'t load expense types'), findsOneWidget);

    types.failing = false;
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Couldn\'t load expense types'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Update draft'));
    await tester.pumpAndSettle();
    final attachments = api.drafts.single['expenseAttachments'] as List;
    // 'food' is active and stays; 'retired' is unknown now and asks again.
    expect(attachments.map((a) => a['cost_type']), ['food', '']);
  });

  testWidgets('choosing a type from a wallet row chip updates that receipt', (
    tester,
  ) async {
    final api = _RecordingApi();
    await pumpBisoScreen(
      tester,
      CreateExpenseScreen(draftExpense: _draft),
      overrides: _overrides(
        _FlakyTypes(failing: false, types: const [_food]),
        api,
      ),
    );
    await tester.pumpAndSettle();

    // The retired slug asks again; the chip sits on its wallet row.
    expect(find.text('Choose a type'), findsOneWidget);
    await tester.tap(find.text('Choose a type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food').last);
    await tester.pumpAndSettle();
    expect(find.text('Choose a type'), findsNothing);
    expect(find.text('Food'), findsNWidgets(2));

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Update draft'));
    await tester.pumpAndSettle();
    final attachments = api.drafts.single['expenseAttachments'] as List;
    expect(attachments.map((a) => a['cost_type']), ['food', 'food']);
  });
}
