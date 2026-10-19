import 'package:biso/data/models/expense_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExpenseModel', () {
    test('reads the financial-manager flag and cost type from a saved draft', () {
      final draft = ExpenseModel.fromMap({
        '\$id': 'expense-3',
        'userId': 'user-3',
        'campus': '1',
        'department': 'dept',
        'total': 10,
        'submitter_is_financial_manager': true,
        'expenseAttachments': [
          {'type': 'image/jpeg', 'cost_type': 'travel'},
        ],
      });
      expect(draft.submitterIsFinancialManager, isTrue);
      expect(draft.expenseAttachments.first.costType, 'travel');
      expect(
        ExpenseModel.fromMap({
          '\$id': 'e',
          'userId': 'u',
          'campus': 'c',
          'department': 'd',
          'total': 0,
        }).submitterIsFinancialManager,
        isFalse,
      );
    });

    test('uses shared Norwegian account validation and formatting', () {
      const expense = ExpenseModel(
        id: 'expense-1',
        userId: 'user-1',
        campus: 'oslo',
        department: 'finance',
        bankAccount: '86011117947',
        total: 199.0,
      );

      expect(expense.isValidBankAccount, isTrue);
      expect(expense.formattedBankAccount, '8601 11 17947');
    });

    test('parses minimal map data safely', () {
      final expense = ExpenseModel.fromMap({
        '\$id': 'expense-2',
        'userId': 'user-2',
        'campus': 'bergen',
        'department': 'marketing',
        'bank_account': '86011117947',
        'total': 49,
      });

      expect(expense.id, 'expense-2');
      expect(expense.total, 49.0);
      expect(expense.expenseAttachments, isEmpty);
    });
  });
}
