import 'package:biso/data/models/expense_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExpenseModel', () {
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
