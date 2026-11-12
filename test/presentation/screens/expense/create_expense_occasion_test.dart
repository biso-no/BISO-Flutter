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
import 'package:biso/presentation/screens/expense/widgets/receipt_notices.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/config/app_config_provider.dart';
import 'package:biso/providers/expense/expense_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

/// The occasion question, the submit checks and the server's occasion error.

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

const _occasionLabel = 'What was the occasion, and who attended?';

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

class _Types extends ExpenseCostTypeService {
  @override
  Future<List<ExpenseCostTypeOption>> listActive() async => const [
    ExpenseCostTypeOption(slug: 'food', label: 'Food'),
    ExpenseCostTypeOption(slug: 'dinner', label: 'Dinner', askOccasion: true),
  ];
}

class _RecordingApi extends ExpenseApiClient {
  final List<Map<String, dynamic>> drafts = [];
  final List<Map<String, dynamic>> submits = [];
  Object? submitError;

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

  @override
  Future<ExpenseSubmitResult> submit(Map<String, dynamic> payload) async {
    submits.add(payload);
    final error = submitError;
    if (error != null) throw error;
    return const ExpenseSubmitResult(success: true);
  }
}

ExpenseAttachmentModel _attachment(String id, {String? costType}) =>
    ExpenseAttachmentModel(
      id: id,
      url: 'file-$id',
      amount: 120,
      description: 'Receipt $id',
      type: 'image/jpeg',
      costType: costType,
    );

ExpenseModel _draft(List<ExpenseAttachmentModel> attachments) => ExpenseModel(
  id: 'draft-1',
  userId: 'u1',
  campus: 'c1',
  department: 'd1',
  bankAccount: '86011117947',
  description: 'Trip',
  total: 120.0 * attachments.length,
  status: 'draft',
  expenseAttachments: attachments,
);

Future<_RecordingApi> _pump(
  WidgetTester tester,
  ExpenseModel draft, {
  Object? submitError,
}) async {
  final api = _RecordingApi()..submitError = submitError;
  await pumpBisoScreen(
    tester,
    CreateExpenseScreen(draftExpense: draft),
    overrides: <Override>[
      expenseCostTypeServiceProvider.overrideWithValue(_Types()),
      authStateProvider.overrideWith(() => _Auth()),
      expenseServiceProvider.overrideWithValue(_FakeExpenseService()),
      expenseApiClientProvider.overrideWithValue(api),
      appConfigProvider.overrideWith(
        (_) async => const AppConfig(expensesEnabled: true),
      ),
    ],
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Report'));
  await tester.pumpAndSettle();
  return api;
}

Future<void> _tapSubmit(WidgetTester tester) async {
  await tester.tap(find.text('Submit'));
  await tester.pumpAndSettle();
}

bool _occasionHasFocus(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('expense-occasion-field')),
        matching: find.byType(EditableText),
      ),
    )
    .focusNode
    .hasFocus;

void main() {
  testWidgets('submit is blocked and the first missing receipt is opened', (
    tester,
  ) async {
    final api = await _pump(
      tester,
      _draft([_attachment('a1'), _attachment('a2', costType: 'food')]),
    );
    await _tapSubmit(tester);

    expect(api.submits, isEmpty);
    expect(find.text('Choose a type for 1 receipt'), findsOneWidget);
    // The picker for the missing receipt is open.
    expect(find.text('Expense type'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
    // On a phone the Receipts tab is showing.
    expect(find.text('Receipts'), findsWidgets);
    expect(find.byKey(const ValueKey('expense-occasion-field')), findsNothing);
  });

  testWidgets('occasion shows when a chosen type asks for it', (tester) async {
    await _pump(tester, _draft([_attachment('a1', costType: 'food')]));
    expect(find.text(_occasionLabel), findsNothing);
  });

  testWidgets('a type that asks for the occasion shows the field and blocks '
      'submit until it is answered', (tester) async {
    final api = await _pump(
      tester,
      _draft([_attachment('a1', costType: 'dinner')]),
    );
    expect(find.text(_occasionLabel), findsOneWidget);

    await _tapSubmit(tester);
    expect(api.submits, isEmpty);
    expect(find.text('Answer this before you submit'), findsOneWidget);
    expect(_occasionHasFocus(tester), isTrue);

    await tester.enterText(
      find.byKey(const ValueKey('expense-occasion-field')),
      'Board dinner, six members',
    );
    await _tapSubmit(tester);
    expect(api.submits, hasLength(1));
    expect(api.submits.single['occasion'], 'Board dinner, six members');
  });

  testWidgets('occasion 400 focuses the field and keeps the draft id', (
    tester,
  ) async {
    final api = await _pump(
      tester,
      _draft([_attachment('a1', costType: 'food')]),
      submitError: const ExpenseApiException(
        'Occasion is required',
        statusCode: 400,
        field: 'occasion',
        expenseId: 'server-draft',
      ),
    );
    expect(find.text(_occasionLabel), findsNothing);

    await _tapSubmit(tester);
    expect(find.text(_occasionLabel), findsOneWidget);
    expect(find.text('Answer this before you submit'), findsOneWidget);
    expect(find.text('Occasion is required'), findsNothing);
    expect(_occasionHasFocus(tester), isTrue);

    api.submitError = null;
    await tester.enterText(
      find.byKey(const ValueKey('expense-occasion-field')),
      'Team lunch',
    );
    await _tapSubmit(tester);
    expect(api.submits, hasLength(2));
    expect(api.submits.last['expenseId'], 'server-draft');
    expect(api.submits.last['occasion'], 'Team lunch');
  });

  testWidgets('blank occasion is sent as null', (tester) async {
    final api = await _pump(
      tester,
      _draft([_attachment('a1', costType: 'food')]),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Update draft'));
    await tester.pumpAndSettle();
    expect(api.drafts.single.containsKey('occasion'), isTrue);
    expect(api.drafts.single['occasion'], isNull);
  });

  testWidgets('a draft saves without an answer and a saved occasion is '
      'hydrated', (tester) async {
    final api = await _pump(
      tester,
      _draft([_attachment('a1', costType: 'dinner')])
          .copyWith(occasion: 'Kickoff'),
    );
    expect(find.text('Kickoff'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Update draft'));
    await tester.pumpAndSettle();
    expect(api.drafts.single['occasion'], 'Kickoff');
  });

  testWidgets('the report row shows its notices', (tester) async {
    await _pump(tester, _draft([_attachment('a1', costType: 'food')]));
    // Hydrated drafts carry no scan results, so no notices yet.
    expect(find.byType(ReceiptNotices), findsWidgets);
    expect(find.text('Hard to read. A clearer photo helps'), findsNothing);
  });
}
