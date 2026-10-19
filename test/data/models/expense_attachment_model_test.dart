import 'package:biso/data/models/expense_attachment_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const receipt = ExpenseAttachmentModel(
    id: 'a1',
    type: 'image/jpeg',
    amount: 120,
    costType: 'travel',
  );

  test('copyWith keeps the cost type when it is not given', () {
    expect(receipt.copyWith(amount: 150).costType, 'travel');
  });

  test('copyWith sets a new cost type', () {
    final changed = receipt.copyWith(costType: 'academic');

    expect(changed.costType, 'academic');
    expect(changed.amount, 120);
    expect(changed.type, 'image/jpeg');
  });
}
