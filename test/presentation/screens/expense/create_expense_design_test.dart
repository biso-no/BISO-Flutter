import 'package:biso/data/models/expense_attachment_model.dart';
import 'package:biso/data/models/expense_model.dart';
import 'package:biso/data/models/user_model.dart';
import 'package:biso/data/services/expense_service_v2.dart';
import 'package:biso/presentation/screens/expense/create_expense_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/expense/expense_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth(UserModel? user)
    : super(AuthState(isAuthenticated: user != null, user: user));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Never touches Appwrite: `_loadLookups` (called from `initState`) always
/// awaits `listCampuses`/`listDepartmentsForCampus`, so a real
/// `ExpenseServiceV2` would try a network call and hang the test. Both
/// resolve immediately and offline, mirroring `_FakeExpenseService` in
/// expenses_design_test.dart.
class _FakeExpenseService extends ExpenseServiceV2 {
  _FakeExpenseService({this.campuses = const [], this.departments = const []});

  final List<Map<String, dynamic>> campuses;
  final List<Map<String, dynamic>> departments;

  @override
  Future<List<Map<String, dynamic>>> listCampuses() async => campuses;

  @override
  Future<List<Map<String, dynamic>>> listDepartmentsForCampus(
    String campusId,
  ) async => departments;
}

const _campus = {'\$id': 'c1', 'name': 'Oslo'};
const _department = {'Id': 'd1', 'Name': 'Marketing'};

const _incompleteUser = UserModel(
  id: 'u1',
  name: 'Kari Nordmann',
  email: 'kari@bi.no',
  campusId: 'c1',
);

List<Override> _overrides({
  UserModel? user = _incompleteUser,
  List<Map<String, dynamic>> campuses = const [_campus],
  List<Map<String, dynamic>> departments = const [_department],
}) => [
  authStateProvider.overrideWith((_) => _Auth(user)),
  expenseServiceProvider.overrideWithValue(
    _FakeExpenseService(campuses: campuses, departments: departments),
  ),
];

void main() {
  testWidgets(
    'New expense builds on BisoPage in every appearance: the cost '
    'allocation gate and the report pane',
    (tester) async {
      // No campus on the user yet: `_loadLookups` cannot complete an
      // assignment, so the gate (campus/department pickers) renders.
      await expectBuildsCleanly(
        tester,
        () => const CreateExpenseScreen(),
        overrides: _overrides(
          user: const UserModel(id: 'u1', name: 'Kari', email: 'kari@bi.no'),
        ),
      );

      // A draft whose campus/department already match the fake lookups:
      // `_hasAssignment` is true as soon as `_loadLookups` resolves, so the
      // wallet/report split renders instead of the gate.
      await expectBuildsCleanly(
        tester,
        () => CreateExpenseScreen(
          draftExpense: ExpenseModel(
            id: 'draft-1',
            userId: 'u1',
            campus: 'c1',
            department: 'd1',
            bankAccount: '',
            total: 0,
            status: 'draft',
          ),
        ),
        overrides: _overrides(),
      );
    },
  );

  testWidgets(
    'tapping close on a dirty form (a resumed draft) shows the existing '
    'leave-reimbursement confirmation dialog',
    (tester) async {
      await pumpBisoScreen(
        tester,
        CreateExpenseScreen(
          draftExpense: ExpenseModel(
            id: 'draft-1',
            userId: 'u1',
            campus: 'c1',
            department: '',
            bankAccount: '',
            total: 0,
            status: 'draft',
          ),
        ),
        overrides: _overrides(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Leave reimbursement?'), findsNothing);

      // English MaterialLocalizations' closeButtonTooltip.
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Leave reimbursement?'), findsOneWidget);

      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();

      expect(find.text('Leave reimbursement?'), findsNothing);
    },
  );

  testWidgets(
    'an invalid MOD11 bank account entered in the complete-profile sheet '
    'shows the existing validation message',
    (tester) async {
      // Missing everything but campus/bank, so the profile-incomplete
      // banner (with its "Update" action opening the sheet) renders in the
      // report pane.
      await pumpBisoScreen(
        tester,
        CreateExpenseScreen(
          draftExpense: ExpenseModel(
            id: 'draft-1',
            userId: 'u1',
            campus: 'c1',
            department: 'd1',
            bankAccount: '',
            total: 0,
            status: 'draft',
          ),
        ),
        overrides: _overrides(),
        size: const Size(820, 1024), // wide layout: report pane always visible
      );
      await tester.pumpAndSettle();

      expect(find.text('Complete your profile'), findsOneWidget);
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();

      expect(find.text('Complete profile'), findsOneWidget);

      // '86011117948' is a known MOD11-checksum failure (from
      // norwegian_bank_account_test.dart): 11 digits, but the check digit
      // doesn't match, so the existing validator's exact message shows —
      // as a SnackBar, since that's how this screen has always surfaced it
      // (not inline below the field; see the task report's deviations).
      await tester.enterText(
        find.descendant(
          of: find.widgetWithText(BisoFormRow, 'Bank account'),
          matching: find.byType(TextField),
        ),
        '86011117948',
      );
      await tester.tap(find.text('Save profile'));
      await tester.pump();

      expect(find.text('Invalid Norwegian bank account number'), findsOneWidget);
    },
  );

  testWidgets(
    'a large receipt amount renders in full at 1.6x text on the wide '
    '(side-by-side) layout, in both brightnesses (R11)',
    (tester) async {
      final draft = ExpenseModel(
        id: 'draft-1',
        userId: 'u1',
        campus: 'c1',
        department: 'd1',
        bankAccount: '86011117947',
        total: 12345.50,
        status: 'draft',
        expenseAttachments: const [
          ExpenseAttachmentModel(
            id: 'a1',
            url: 'https://appwrite.biso.no/v1/storage/buckets/b/files/file123/view',
            amount: 12345.50,
            description: 'A very large taxi receipt',
            type: 'image/jpeg',
          ),
        ],
      );

      for (final brightness in Brightness.values) {
        await pumpBisoScreen(
          tester,
          CreateExpenseScreen(draftExpense: draft),
          overrides: _overrides(
            user: const UserModel(
              id: 'u1',
              name: 'Kari Nordmann',
              email: 'kari@bi.no',
              phone: '12345678',
              address: 'Nydalsveien 15',
              city: 'Oslo',
              zipCode: '0484',
              campusId: 'c1',
              bankAccount: '86011117947',
            ),
          ),
          brightness: brightness,
          textScale: 1.6,
          size: const Size(900, 844),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$brightness');

        final amountFinder = find.text('NOK 12345.50');
        expect(amountFinder, findsWidgets, reason: '$brightness');
        for (final element in amountFinder.evaluate()) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.byWidget(element.widget),
          );
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: 'NOK 12345.50 was ellipsized ($brightness)',
          );
        }

        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
