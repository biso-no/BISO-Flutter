import 'package:equatable/equatable.dart';

import '../../data/models/campus_benefit.dart';

/// Why a deal is in the "Utvalgt" picks.
enum FeaturedReason { pickedByBiso, endingSoon, isNew }

/// A deal in the picks, with the reason it was picked (null on the Home
/// fallback, where the first deals stand in for picks).
class FeaturedBenefit extends Equatable {
  const FeaturedBenefit(this.benefit, this.reason);

  final CampusBenefit benefit;
  final FeaturedReason? reason;

  @override
  List<Object?> get props => [benefit, reason];
}

/// Catalogue order, as on the website.
const benefitCategoryKeys = [
  'food_drink',
  'health_fitness',
  'nightlife',
  'shopping',
  'travel',
  'software',
  'events',
  'other',
];

const _otherCategory = 'other';
const _maxFeatured = 5;
const _endingSoonWindow = Duration(days: 30);
const _newWindow = Duration(days: 14);

/// The catalogue key of [b]; an unknown or missing category is `other`.
String benefitCategoryKeyOf(CampusBenefit b) {
  final key = b.category;
  return key != null && benefitCategoryKeys.contains(key)
      ? key
      : _otherCategory;
}

/// The benefits list split into what the screen shows.
class BenefitShowcase {
  const BenefitShowcase._({
    required this.deals,
    required this.featured,
    required this.perks,
    required this.categories,
    required this.imageUrls,
  });

  factory BenefitShowcase.from(
    List<CampusBenefit> all, {
    required DateTime now,
  }) {
    final deals = [
      for (final b in all)
        if (b.section == BenefitSection.member) b,
    ];

    final perks = <BenefitSection, List<CampusBenefit>>{};
    for (final section in const [
      BenefitSection.career,
      BenefitSection.social,
      BenefitSection.safety,
    ]) {
      final items = [
        for (final b in all)
          if (b.section == section) b,
      ];
      if (items.isNotEmpty) perks[section] = items;
    }

    final soonLimit = now.add(_endingSoonWindow);
    final newLimit = now.subtract(_newWindow);
    bool endingSoon(CampusBenefit b) {
      final end = b.publishEnd;
      return end != null && end.isAfter(now) && !end.isAfter(soonLimit);
    }

    bool isNew(CampusBenefit b) {
      final created = b.createdAt;
      return created != null && !created.isBefore(newLimit);
    }

    final featured = <FeaturedBenefit>[];
    final seen = <String>{};
    void take(bool Function(CampusBenefit) test, FeaturedReason reason) {
      for (final b in deals) {
        if (featured.length >= _maxFeatured) return;
        if (seen.contains(b.id) || !test(b)) continue;
        seen.add(b.id);
        featured.add(FeaturedBenefit(b, reason));
      }
    }

    take((b) => b.isFeatured, FeaturedReason.pickedByBiso);
    take(endingSoon, FeaturedReason.endingSoon);
    take(isNew, FeaturedReason.isNew);

    final present = {for (final b in deals) benefitCategoryKeyOf(b)};
    final categories = [
      for (final key in benefitCategoryKeys)
        if (present.contains(key)) key,
    ];

    final imageUrls = <String>{
      for (final b in deals) ?(b.partner?.logoUrl ?? b.imageUrl),
    }.toList();

    return BenefitShowcase._(
      deals: deals,
      featured: featured,
      perks: perks,
      categories: categories,
      imageUrls: imageUrls,
    );
  }

  /// Section member, in the API's order.
  final List<CampusBenefit> deals;

  /// At most five deals, each with a reason.
  final List<FeaturedBenefit> featured;

  /// Career, social and safety in that order; empty lists are left out.
  final Map<BenefitSection, List<CampusBenefit>> perks;

  /// Category keys present in [deals], in catalogue order.
  final List<String> categories;

  /// Distinct partner logo (else image) URLs, in deals order.
  final List<String> imageUrls;

  int get count =>
      deals.length + perks.values.fold(0, (sum, list) => sum + list.length);

  bool get isEmpty => deals.isEmpty && perks.isEmpty;

  /// The picks, else the first five deals with no reason.
  List<FeaturedBenefit> get homeItems => featured.isNotEmpty
      ? featured
      : [for (final b in deals.take(_maxFeatured)) FeaturedBenefit(b, null)];
}
