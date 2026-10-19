/// Dart port of `BISO-Sites/packages/shared/utils/expense-cost-types.ts`.
///
/// A cost type is the label a student picks for a receipt; apps/api resolves
/// its slug to the ledger account the line is booked to. The web offers these
/// same defaults, so the slugs here must stay in step with it.
class ExpenseCostType {
  final String slug;
  final String label;

  const ExpenseCostType({required this.slug, required this.label});
}

const defaultExpenseCostTypes = <ExpenseCostType>[
  ExpenseCostType(slug: 'travel', label: 'Travel'),
  ExpenseCostType(slug: 'social', label: 'Social event'),
  ExpenseCostType(slug: 'academic', label: 'Academic event'),
  ExpenseCostType(slug: 'other', label: 'Other'),
];

const defaultCostTypeSlug = 'other';

const _ocrCategoryToSlug = <String, String>{
  'travel': 'travel',
  'accommodation': 'travel',
  'meal': 'social',
  'event-materials': 'academic',
  'supplies': 'other',
  'fee': 'other',
  'other': 'other',
};

/// The cost-type slug a receipt gets until the student changes it, from the
/// category OCR read off the receipt.
String defaultCostTypeSlugForCategory(String? category) {
  return _ocrCategoryToSlug[category] ?? defaultCostTypeSlug;
}
