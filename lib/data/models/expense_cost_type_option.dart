import 'dart:ui' show Locale;

/// One expense type a student can pick, read from `expense_cost_types`.
/// Account numbers and tax codes live in the same row but are never read here.
class ExpenseCostTypeOption {
  final String slug;
  final String label;
  final String? labelNo;
  final bool askOccasion;
  final int sortOrder;

  const ExpenseCostTypeOption({
    required this.slug,
    required this.label,
    this.labelNo,
    this.askOccasion = false,
    this.sortOrder = 0,
  });

  factory ExpenseCostTypeOption.fromRow(Map<String, dynamic> data) {
    final labelNo = data['label_no']?.toString();
    return ExpenseCostTypeOption(
      slug: data['slug'].toString(),
      label: (data['label'] ?? data['slug']).toString(),
      labelNo: labelNo == null || labelNo.trim().isEmpty ? null : labelNo,
      askOccasion: data['ask_occasion'] == true,
      sortOrder: (data['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  String labelFor(Locale locale) {
    final isNorwegian =
        locale.languageCode == 'no' || locale.languageCode == 'nb';
    final no = labelNo;
    if (isNorwegian && no != null && no.isNotEmpty) return no;
    return label;
  }
}
