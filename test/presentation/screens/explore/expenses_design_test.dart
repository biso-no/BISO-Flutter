import 'package:biso/data/models/app_config.dart';
import 'package:biso/data/models/expense_model.dart';
import 'package:biso/data/services/expense_service_v2.dart';
import 'package:biso/presentation/screens/explore/expenses_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/config/app_config_provider.dart';
import 'package:biso/providers/expense/expense_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth(bool isAuthenticated)
    : super(AuthState(isAuthenticated: isAuthenticated));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Never touches Appwrite: `ExpensesNotifier` calls `getUserExpenses` from
/// its constructor, so a real `ExpenseServiceV2` would try a network call
/// and hang the test. Every call resolves immediately and offline, mirroring
/// the fakes in events_design_test.dart / jobs_design_test.dart.
class _FakeExpenseService extends ExpenseServiceV2 {
  _FakeExpenseService(this._expenses);

  final List<ExpenseModel> _expenses;

  @override
  Future<List<ExpenseModel>> getUserExpenses({
    String? userId,
    List<String> queries = const [],
  }) async => _expenses;
}

ExpenseModel _expense({
  required String id,
  String? description,
  String department = 'Marketing',
  double total = 500,
  String status = 'pending',
  DateTime? createdAt,
  DateTime? approvedAt,
  String? approverName,
  String? rejectionReason,
}) => ExpenseModel(
  id: id,
  userId: 'user-1',
  campus: 'oslo',
  department: department,
  bankAccount: '12345678903',
  description: description,
  total: total,
  status: status,
  createdAt: createdAt ?? DateTime(2026, 3, 4),
  approvedAt: approvedAt,
  approverName: approverName,
  rejectionReason: rejectionReason,
);

List<Override> _overrides(
  List<ExpenseModel> expenses, {
  bool authenticated = true,
}) => [
  authStateProvider.overrideWith((_) => _Auth(authenticated)),
  expenseServiceProvider.overrideWithValue(_FakeExpenseService(expenses)),
  appConfigProvider.overrideWith(
    (_) async => const AppConfig(expensesEnabled: true),
  ),
];

/// Asserts [text] renders as a single, complete, full-size line — R11:
/// amounts never truncate, wrap, or scale down. Mirrors the check in
/// orders_design_test.dart.
void _expectFullSizeAmount(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(
    finder,
    findsAtLeastNWidgets(1),
    reason: '"$text" should render in full',
  );
  for (final element in finder.evaluate()) {
    final widgetFinder = find.byWidget(element.widget);
    expect(
      find.ancestor(of: widgetFinder, matching: find.byType(FittedBox)),
      findsNothing,
      reason: '"$text" is inside a FittedBox and so may be scaled down',
    );
    final paragraph = tester.renderObject<RenderParagraph>(widgetFinder);
    expect(paragraph.maxLines, 1, reason: '"$text" should be one line');
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: '"$text" was ellipsized',
    );
    final maxIntrinsicWidth = paragraph.getMaxIntrinsicWidth(double.infinity);
    expect(
      paragraph.size.width,
      greaterThanOrEqualTo(maxIntrinsicWidth - 0.5),
      reason: '"$text" was laid out narrower than its natural width',
    );
  }
}

void main() {
  testWidgets(
    'Expenses builds on BisoPage in every appearance: signed out, empty, '
    'and with expenses in every status',
    (tester) async {
      await expectBuildsCleanly(
        tester,
        () => const ExpensesScreen(),
        overrides: _overrides(const [], authenticated: false),
      );

      await expectBuildsCleanly(
        tester,
        () => const ExpensesScreen(),
        overrides: _overrides(const []),
      );

      await expectBuildsCleanly(
        tester,
        () => const ExpensesScreen(),
        overrides: _overrides([
          _expense(id: '1', description: 'Taxi to airport', status: 'draft'),
          _expense(
            id: '2',
            description: 'Conference tickets',
            status: 'pending',
          ),
          _expense(id: '3', description: 'Team lunch', status: 'submitted'),
          _expense(id: '4', description: 'Printer paper', status: 'success'),
          _expense(
            id: '5',
            description: 'Late receipt',
            status: 'rejected',
            rejectionReason: 'Missing receipt',
          ),
        ]),
      );
    },
  );

  testWidgets(
    'there is no FloatingActionButton, and the header has a New Expense '
    'tooltip',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const ExpensesScreen(),
        overrides: _overrides([
          _expense(id: '1', description: 'Taxi', status: 'pending'),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byTooltip('New Expense'), findsOneWidget);
    },
  );

  testWidgets(
    'typing in header search filters the fake expenses down to one row',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const ExpensesScreen(),
        overrides: _overrides([
          _expense(
            id: '1',
            description: 'Taxi to airport',
            department: 'Marketing',
          ),
          _expense(
            id: '2',
            description: 'Conference tickets',
            department: 'Finance',
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Taxi to airport'), findsOneWidget);
      expect(find.text('Conference tickets'), findsOneWidget);

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'taxi');
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Taxi to airport'), findsOneWidget);
      expect(find.text('Conference tickets'), findsNothing);
    },
  );

  testWidgets(
    'the status pill token matches every known status, in light and dark',
    (tester) async {
      const expected = {
        'draft': 'Draft',
        'pending': 'Pending',
        'submitted': 'Submitted',
        'success': 'Success',
        'rejected': 'Rejected',
      };
      Color expectedColor(String status, BisoPalette palette) {
        switch (status) {
          case 'success':
            return palette.success;
          case 'rejected':
            return palette.error;
          default:
            return palette.warning;
        }
      }

      for (final entry in expected.entries) {
        for (final brightness in Brightness.values) {
          await pumpBisoScreen(
            tester,
            const ExpensesScreen(),
            overrides: _overrides([
              _expense(
                id: 'e-${entry.key}',
                description: 'Uniquely Named Item',
                status: entry.key,
              ),
            ]),
            brightness: brightness,
          );
          await tester.pumpAndSettle();

          // "Draft"/"Pending"/etc. also appear as a filter chip label and
          // (for 'draft'/'pending') a summary-card total label, so the pill
          // is located specifically inside the expense's own row.
          final rowFinder = find.ancestor(
            of: find.text('Uniquely Named Item'),
            matching: find.byType(BisoListRow),
          );
          expect(rowFinder, findsOneWidget, reason: '${entry.key} ($brightness)');
          final pillFinder = find.descendant(
            of: rowFinder,
            matching: find.text(entry.value),
          );
          expect(pillFinder, findsOneWidget, reason: '${entry.key} ($brightness)');
          final palette = brightness == Brightness.dark
              ? BisoPalette.dark
              : BisoPalette.light;
          final pillText = tester.widget<Text>(pillFinder);
          expect(
            pillText.style?.color,
            expectedColor(entry.key, palette),
            reason: '${entry.key} ($brightness)',
          );

          await tester.pumpWidget(const SizedBox());
        }
      }
    },
  );

  testWidgets(
    'the summary total and a large row amount render in full at 1.6x text, '
    'on both 320pt and 390pt phones (R11)',
    (tester) async {
      // A whole-number total keeps the summary card (0-decimal display) and
      // the row/detail-sheet amount (formattedTotal, 2-decimal display)
      // deterministic, while still exercising a large amount.
      final expense = _expense(
        id: 'big',
        description: 'Large reimbursement',
        status: 'draft',
        total: 12345,
      );

      for (final size in [const Size(320, 844), const Size(390, 844)]) {
        await pumpBisoScreen(
          tester,
          const ExpensesScreen(),
          overrides: _overrides([expense]),
          textScale: 1.6,
          size: size,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$size');

        if (find.text('NOK 12345').evaluate().isNotEmpty) {
          _expectFullSizeAmount(tester, 'NOK 12345');
        } else {
          _expectFullSizeAmount(tester, 'NOK');
          _expectFullSizeAmount(tester, '12345');
        }

        if (find.text('NOK 12345.00').evaluate().isNotEmpty) {
          _expectFullSizeAmount(tester, 'NOK 12345.00');
        } else {
          _expectFullSizeAmount(tester, 'NOK');
          _expectFullSizeAmount(tester, '12345.00');
        }

        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    "the detail sheet's Amount renders in full at 1.6x text, on both 320pt "
    'and 390pt phones (R11)',
    (tester) async {
      final expense = _expense(
        id: 'big',
        description: 'Large reimbursement',
        status: 'draft',
        total: 12345.50,
      );

      for (final size in [const Size(320, 844), const Size(390, 844)]) {
        await pumpBisoScreen(
          tester,
          const ExpensesScreen(),
          overrides: _overrides([expense]),
          textScale: 1.6,
          size: size,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Large reimbursement'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$size');

        if (find.text('NOK 12345.50').evaluate().isNotEmpty) {
          _expectFullSizeAmount(tester, 'NOK 12345.50');
        } else {
          _expectFullSizeAmount(tester, 'NOK');
          _expectFullSizeAmount(tester, '12345.50');
        }

        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'the detail sheet shows the timeline for an approved expense',
    (tester) async {
      final expense = _expense(
        id: 'approved-1',
        description: 'Approved expense',
        status: 'success',
        approvedAt: DateTime(2026, 4, 1, 10, 30),
        approverName: 'Jane Doe',
      );
      await pumpBisoScreen(
        tester,
        const ExpensesScreen(),
        overrides: _overrides([expense]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Approved expense'));
      await tester.pumpAndSettle();

      expect(find.text('Created'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.textContaining('Jane Doe'), findsOneWidget);
    },
  );

  testWidgets('the more action tooltip is localized in Norwegian', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const ExpensesScreen(),
      overrides: _overrides([
        _expense(id: '1', description: 'Taxi', status: 'pending'),
      ]),
      locale: const Locale('no'),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Mer'), findsOneWidget);
  });
}
