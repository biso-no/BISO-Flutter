import 'package:biso/data/models/app_config.dart';
import 'package:biso/data/models/expense_attachment_model.dart';
import 'package:biso/data/models/expense_model.dart';
import 'package:biso/data/models/expense_v2_models.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/expense_api_client.dart';
import 'package:biso/data/services/expense_service_v2.dart';
import 'package:biso/presentation/screens/expense/create_expense_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/config/app_config_provider.dart';
import 'package:biso/providers/expense/expense_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

/// The campus and department lists behind the cost-allocation form. When one
/// of them fails, the form says so and offers to try again; once it has
/// loaded, neither the failure nor its "Try again" may linger — a stale
/// retry would reset the campus the student has chosen since.

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

/// Both campuses load; the first [failures] department reads fail.
class _FlakyDepartments extends ExpenseServiceV2 {
  _FlakyDepartments({required this.failures});

  int failures;
  final List<String> departmentReads = [];

  @override
  Future<List<ExpenseModel>> getUserExpenses({
    String? userId,
    List<String> queries = const [],
  }) async => const [];

  @override
  Future<List<Map<String, dynamic>>> listCampuses() async => const [
    {'\$id': 'c1', 'name': 'Oslo'},
    {'\$id': 'c2', 'name': 'Bergen'},
  ];

  @override
  Future<List<Map<String, dynamic>>> listDepartmentsForCampus(
    String campusId,
  ) async {
    departmentReads.add(campusId);
    if (failures > 0) {
      failures--;
      throw Exception('offline');
    }
    return const [
      {'Id': 'd1', 'Name': 'Marketing'},
    ];
  }
}

/// The config is known from the first frame, so the screen's own retry —
/// which fires when the config's answer arrives after a lookup failed — does
/// not run: these tests are about what the student can do.
/// Choosing a department with a ready receipt asks the API for an accounting
/// summary; answer it offline.
class _OfflineApi extends ExpenseApiClient {
  @override
  Future<String> summarize({
    required ExpenseAssignment assignment,
    required List<ExpenseReceiptDraft> receipts,
  }) async => '';
}

List<Override> _overrides(_FlakyDepartments lookups) => [
  authStateProvider.overrideWith((_) => _Auth()),
  expenseServiceProvider.overrideWithValue(lookups),
  expenseApiClientProvider.overrideWithValue(_OfflineApi()),
  appConfigProvider.overrideWith(
    (_) => SynchronousFuture(const AppConfig(expensesEnabled: true)),
  ),
];

BisoListRow _row(WidgetTester tester, String title) =>
    tester.widget<BisoListRow>(
      find.byWidgetPredicate(
        (widget) => widget is BisoListRow && widget.title == title,
      ),
    );

final _retry = find.widgetWithText(TextButton, 'Try again');

Future<void> _pickCampus(WidgetTester tester, String name) async {
  await tester.tap(find.text('Campus'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a department list that loads after a failure clears the '
      'failure', (tester) async {
    final lookups = _FlakyDepartments(failures: 1);
    await pumpBisoScreen(
      tester,
      const CreateExpenseScreen(),
      overrides: _overrides(lookups),
    );
    await tester.pumpAndSettle();

    // The campus list loaded; the departments for Oslo did not.
    expect(find.textContaining('Failed to load departments'), findsOneWidget);
    expect(_retry, findsOneWidget);

    await _pickCampus(tester, 'Bergen');

    expect(lookups.departmentReads, ['c1', 'c2']);
    expect(find.textContaining('Failed to load'), findsNothing);
    expect(_retry, findsNothing);
    expect(_row(tester, 'Campus').value, 'Bergen');
    expect(_row(tester, 'Department').onTap, isNotNull);
  });

  testWidgets('trying again keeps the campus the student chose', (
    tester,
  ) async {
    final lookups = _FlakyDepartments(failures: 2);
    await pumpBisoScreen(
      tester,
      const CreateExpenseScreen(),
      overrides: _overrides(lookups),
    );
    await tester.pumpAndSettle();

    // Bergen's departments fail too — that failure has to be said, and it
    // is what "Try again" now retries.
    await _pickCampus(tester, 'Bergen');
    expect(find.textContaining('Failed to load departments'), findsOneWidget);
    expect(_retry, findsOneWidget);

    await tester.tap(_retry);
    await tester.pumpAndSettle();

    expect(lookups.departmentReads, ['c1', 'c2', 'c2']);
    expect(_row(tester, 'Campus').value, 'Bergen');
    expect(find.textContaining('Failed to load'), findsNothing);
    expect(_row(tester, 'Department').onTap, isNotNull);
  });

  testWidgets('a draft keeps its receipts when only the departments failed', (
    tester,
  ) async {
    final lookups = _FlakyDepartments(failures: 1);
    // No department yet, so the draft opens on the cost-allocation form.
    final draft = ExpenseModel(
      id: 'draft-1',
      userId: 'u1',
      campus: 'c1',
      department: '',
      bankAccount: '',
      total: 120,
      status: 'draft',
      expenseAttachments: const [
        ExpenseAttachmentModel(
          id: 'a1',
          url:
              'https://appwrite.biso.no/v1/storage/buckets/b/files/file123/view',
          amount: 120,
          description: 'Taxi',
          type: 'image/jpeg',
        ),
      ],
    );
    await pumpBisoScreen(
      tester,
      CreateExpenseScreen(draftExpense: draft),
      overrides: _overrides(lookups),
    );
    await tester.pumpAndSettle();
    expect(_retry, findsOneWidget);

    await tester.tap(_retry);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Department'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marketing'));
    await tester.pumpAndSettle();

    // The draft's receipt is there: saving now must not drop it.
    expect(find.text('Receipt wallet'), findsOneWidget);
    expect(find.text('file123'), findsOneWidget);
    expect(find.text('No receipts yet'), findsNothing);
  });
}
