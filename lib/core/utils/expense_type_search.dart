import 'dart:ui' show Locale;

import '../../data/models/expense_cost_type_option.dart';

final _whitespace = RegExp(r'\s+');

/// Lowercases, maps `æ`→`ae`, `ø`→`o`, `å`→`a`, drops other accents and
/// collapses whitespace, so "Mat og drikke" and "mat  og DRIKKE" compare equal.
String foldForSearch(String input) {
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_foldMap[char] ?? char);
  }
  return buffer.toString().replaceAll(_whitespace, ' ').trim();
}

const _foldMap = <String, String>{
  'æ': 'ae',
  'ø': 'o',
  'å': 'a',
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
};

List<ExpenseCostTypeOption> _bySortOrder(List<ExpenseCostTypeOption> types) =>
    [...types]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

/// The types matching [query] in either language, prefix matches of the shown
/// label first. An empty query returns every type in `sortOrder`.
List<ExpenseCostTypeOption> searchTypes(
  List<ExpenseCostTypeOption> types,
  String query,
  Locale locale,
) {
  final ordered = _bySortOrder(types);
  final needle = foldForSearch(query);
  if (needle.isEmpty) return ordered;

  final prefix = <ExpenseCostTypeOption>[];
  final rest = <ExpenseCostTypeOption>[];
  for (final type in ordered) {
    final shown = foldForSearch(type.labelFor(locale));
    final labels = [
      shown,
      foldForSearch(type.label),
      if (type.labelNo != null) foldForSearch(type.labelNo!),
    ];
    if (!labels.any((label) => label.contains(needle))) continue;
    (labels.any((label) => label.startsWith(needle)) ? prefix : rest).add(type);
  }
  return [...prefix, ...rest];
}

/// The type whose full label, in either language, equals [query].
ExpenseCostTypeOption? exactTypeMatch(
  List<ExpenseCostTypeOption> types,
  String query,
) {
  final needle = foldForSearch(query);
  if (needle.isEmpty) return null;
  for (final type in _bySortOrder(types)) {
    if (foldForSearch(type.label) == needle ||
        (type.labelNo != null && foldForSearch(type.labelNo!) == needle)) {
      return type;
    }
  }
  return null;
}
