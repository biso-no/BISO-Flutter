import 'dart:ui';

import 'package:biso/core/utils/expense_type_search.dart';
import 'package:biso/data/models/expense_cost_type_option.dart';
import 'package:flutter_test/flutter_test.dart';

const _food = ExpenseCostTypeOption(
  slug: 'food',
  label: 'Food and drink',
  labelNo: 'Mat og drikke',
  sortOrder: 2,
);
const _travel = ExpenseCostTypeOption(
  slug: 'travel',
  label: 'Travel',
  labelNo: 'Reise',
  sortOrder: 1,
);
const _gifts = ExpenseCostTypeOption(
  slug: 'gifts',
  label: 'Gifts for volunteers',
  labelNo: 'Gaver til frivillige',
  sortOrder: 3,
);
const _types = [_food, _travel, _gifts];
const _en = Locale('en');
const _no = Locale('no');

void main() {
  test('foldForSearch folds æøå, other accents, case and whitespace', () {
    expect(foldForSearch('  Ærlig   ØL på Åre '), 'aerlig ol pa are');
    expect(foldForSearch('Café Déjà-vu'), 'cafe deja-vu');
  });

  test('an empty query returns every type in sort order', () {
    expect(searchTypes(_types, '  ', _en), [_travel, _food, _gifts]);
  });

  test('prefix matches of the label come before other matches', () {
    // "r" is in all three; Travel and Reise start with it only in Norwegian.
    final result = searchTypes(_types, 'dr', _en);
    expect(result, [_food]);
    final both = searchTypes(_types, 'o', _en);
    expect(both.first, _food, reason: 'Food starts with no o; falls back');
    expect(searchTypes(_types, 'fo', _en).first, _food);
    expect(searchTypes(_types, 'g', _en).first, _gifts);
  });

  test('prefix first puts a prefix hit ahead of an earlier sort order', () {
    const a = ExpenseCostTypeOption(
      slug: 'a',
      label: 'Other trips',
      sortOrder: 1,
    );
    const b = ExpenseCostTypeOption(slug: 'b', label: 'Trips', sortOrder: 2);
    expect(searchTypes([a, b], 'trip', _en), [b, a]);
  });

  test('matches the other language and folds Norwegian letters', () {
    expect(searchTypes(_types, 'reise', _en), [_travel]);
    expect(searchTypes(_types, 'travel', _no), [_travel]);
    expect(searchTypes(_types, 'gaver', _en), [_gifts]);
    expect(searchTypes(_types, 'zzz', _en), isEmpty);
  });

  test('exactTypeMatch matches a full label in either language', () {
    expect(exactTypeMatch(_types, 'food and drink'), _food);
    expect(exactTypeMatch(_types, ' MAT  og drikke '), _food);
    expect(exactTypeMatch(_types, 'food'), isNull);
    expect(exactTypeMatch(_types, ''), isNull);
  });
}
