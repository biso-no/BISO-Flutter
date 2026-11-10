import 'package:biso/core/utils/rich_content.dart';
import 'package:biso/data/models/campus_benefit.dart';
import 'package:equatable/equatable.dart';

enum BenefitHighlightKind { percent, free, price }

/// The discount a deal states in its own text: "25 %", "Gratis", "150 kr".
class BenefitHighlight extends Equatable {
  const BenefitHighlight.percent(int this.amount)
    : kind = BenefitHighlightKind.percent;
  const BenefitHighlight.price(int this.amount)
    : kind = BenefitHighlightKind.price;
  const BenefitHighlight.free()
    : kind = BenefitHighlightKind.free,
      amount = null;

  final BenefitHighlightKind kind;
  final int? amount;

  @override
  List<Object?> get props => [kind, amount];
}

final _percent = RegExp(r'(?<!\d)(\d{1,2})\s?%');
final _free = RegExp(r'\b(gratis|free)\b', caseSensitive: false);
final _price = RegExp(r'(?<!\d)(\d{2,4})\s?(?:kr\b|,-)', caseSensitive: false);

/// The discount in [benefit]'s title, else its description; null when the
/// text states none. The title is read first and the first rule to match
/// wins (percent, then free, then price).
BenefitHighlight? benefitHighlightOf(
  CampusBenefit benefit,
  String languageCode,
) {
  final texts = [
    benefit.title.resolve(languageCode) ?? '',
    richContentToPlainText(benefit.description.resolve(languageCode) ?? ''),
  ];
  for (final text in texts) {
    final percent = _percent.firstMatch(text);
    if (percent != null) {
      return BenefitHighlight.percent(int.parse(percent.group(1)!));
    }
    if (_free.hasMatch(text)) return const BenefitHighlight.free();
    final price = _price.firstMatch(text);
    if (price != null) {
      return BenefitHighlight.price(int.parse(price.group(1)!));
    }
  }
  return null;
}
