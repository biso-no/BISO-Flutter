import 'package:biso/core/utils/expense_cost_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps every OCR category like the web', () {
    const expected = {
      'travel': 'travel',
      'accommodation': 'travel',
      'meal': 'social',
      'event-materials': 'academic',
      'supplies': 'other',
      'fee': 'other',
      'other': 'other',
    };
    expected.forEach((category, slug) {
      expect(defaultCostTypeSlugForCategory(category), slug, reason: category);
    });
  });

  test('falls back to other for a missing or unknown category', () {
    expect(defaultCostTypeSlugForCategory(null), 'other');
    expect(defaultCostTypeSlugForCategory('gadgets'), 'other');
  });

  test('offers the same cost types as the web', () {
    expect(defaultExpenseCostTypes.map((type) => type.slug), [
      'travel',
      'social',
      'academic',
      'other',
    ]);
    expect(defaultExpenseCostTypes.map((type) => type.label), [
      'Travel',
      'Social event',
      'Academic event',
      'Other',
    ]);
  });
}
