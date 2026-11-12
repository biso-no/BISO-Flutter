import 'dart:ui';

import 'package:biso/data/models/expense_cost_type_option.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final row = {
    'slug': 'food',
    'label': 'Food',
    'label_no': 'Mat',
    'ask_occasion': true,
    'sort_order': 3,
  };

  test('labelFor picks the Norwegian label in Norwegian', () {
    final option = ExpenseCostTypeOption.fromRow(row);
    expect(option.labelFor(const Locale('nb')), 'Mat');
    expect(option.labelFor(const Locale('no')), 'Mat');
    expect(option.labelFor(const Locale('en')), 'Food');
  });

  test('falls back to the English label when label_no is empty', () {
    final option = ExpenseCostTypeOption.fromRow({...row, 'label_no': ''});
    expect(option.labelFor(const Locale('nb')), 'Food');
  });

  test('fromRow reads ask_occasion and sort_order', () {
    final option = ExpenseCostTypeOption.fromRow(row);
    expect(option.slug, 'food');
    expect(option.askOccasion, isTrue);
    expect(option.sortOrder, 3);
    final bare = ExpenseCostTypeOption.fromRow({'slug': 'x', 'label': 'X'});
    expect(bare.askOccasion, isFalse);
    expect(bare.sortOrder, 0);
  });
}
