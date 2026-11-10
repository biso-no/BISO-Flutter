import 'package:biso/data/models/campus_benefit.dart';
import 'package:biso/providers/benefits/benefit_showcase.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 11, 10, 12);

CampusBenefit item(
  String id, {
  BenefitSection section = BenefitSection.member,
  String? category,
  bool featured = false,
  DateTime? end,
  DateTime? created,
  String? imageUrl,
  String? logoUrl,
}) => CampusBenefit(
  id: id,
  campusId: 'c',
  section: section,
  title: BenefitText(nb: id),
  redemptionType: BenefitRedemptionType.none,
  category: category,
  isFeatured: featured,
  publishEnd: end,
  createdAt: created,
  imageUrl: imageUrl,
  partner: logoUrl == null
      ? null
      : BenefitPartner(id: 'p$id', name: 'P', logoUrl: logoUrl),
);

BenefitShowcase show(List<CampusBenefit> l) =>
    BenefitShowcase.from(l, now: now);

List<String> ids(Iterable<CampusBenefit> l) => [for (final b in l) b.id];

void main() {
  test('deals keep API order and only the member section', () {
    final s = show([
      item('b'),
      item('x', section: BenefitSection.career),
      item('a'),
    ]);
    expect(ids(s.deals), ['b', 'a']);
  });

  test('business never shows', () {
    final s = show([
      item('biz', section: BenefitSection.business, featured: true),
    ]);
    expect(s.deals, isEmpty);
    expect(s.perks, isEmpty);
    expect(s.featured, isEmpty);
    expect(s.count, 0);
    expect(s.isEmpty, isTrue);
  });

  test(
    'perks group career, social, safety in that order and skip empty ones',
    () {
      final s = show([
        item('s1', section: BenefitSection.safety),
        item('c1', section: BenefitSection.career),
        item('c2', section: BenefitSection.career),
      ]);
      expect(s.perks.keys.toList(), [
        BenefitSection.career,
        BenefitSection.safety,
      ]);
      expect(ids(s.perks[BenefitSection.career]!), ['c1', 'c2']);
    },
  );

  test('count is deals plus perks', () {
    final s = show([
      item('d'),
      item('c', section: BenefitSection.career),
      item('s', section: BenefitSection.social),
      item('biz', section: BenefitSection.business),
    ]);
    expect(s.count, 3);
    expect(s.isEmpty, isFalse);
  });

  test('featured order: picked by BISO, then ending soon, then new', () {
    final s = show([
      item('new', created: now.subtract(const Duration(days: 1))),
      item('ending', end: now.add(const Duration(days: 3))),
      item('picked', featured: true),
    ]);
    expect(
      [for (final f in s.featured) f.reason],
      [
        FeaturedReason.pickedByBiso,
        FeaturedReason.endingSoon,
        FeaturedReason.isNew,
      ],
    );
    expect(ids([for (final f in s.featured) f.benefit]), [
      'picked',
      'ending',
      'new',
    ]);
  });

  test('featured caps at 5 and lists a deal once', () {
    final one = show([
      item(
        'all',
        featured: true,
        end: now.add(const Duration(days: 3)),
        created: now,
      ),
    ]);
    expect(one.featured.length, 1);
    expect(one.featured.single.reason, FeaturedReason.pickedByBiso);

    final many = show([
      for (var i = 0; i < 8; i++) item('f$i', featured: true),
    ]);
    expect(many.featured.length, 5);
  });

  test('ending soon edge', () {
    final in30 = const Duration(days: 30);
    expect(show([item('a', end: now.add(in30))]).featured.length, 1);
    expect(
      show([
        item('a', end: now.add(in30 + const Duration(minutes: 1))),
      ]).featured,
      isEmpty,
    );
    expect(
      show([item('a', end: now.subtract(const Duration(minutes: 1)))]).featured,
      isEmpty,
    );
  });

  test('new edge', () {
    const d = Duration(days: 14);
    expect(show([item('a', created: now.subtract(d))]).featured.length, 1);
    expect(
      show([
        item('a', created: now.subtract(d + const Duration(minutes: 1))),
      ]).featured,
      isEmpty,
    );
    expect(show([item('a')]).featured, isEmpty);
  });

  test('featured only takes member deals', () {
    final s = show([item('c', section: BenefitSection.career, featured: true)]);
    expect(s.featured, isEmpty);
  });

  test('categories in catalogue order, unknown counted as other', () {
    final s = show([
      item('a', category: 'travel'),
      item('b', category: 'mystery'),
      item('c', category: 'food_drink'),
      item('d'),
    ]);
    expect(s.categories, ['food_drink', 'travel', 'other']);
    expect(benefitCategoryKeyOf(item('z', category: 'nope')), 'other');
    expect(benefitCategoryKeyOf(item('z')), 'other');
  });

  test('imageUrls prefer the partner logo, are distinct and skip nulls', () {
    final s = show([
      item('a', logoUrl: 'logo', imageUrl: 'img'),
      item('b', imageUrl: 'img2'),
      item('c', logoUrl: 'logo'),
      item('d'),
    ]);
    expect(s.imageUrls, ['logo', 'img2']);
  });

  test('homeItems falls back to the first 5 deals without a reason', () {
    final s = show([for (var i = 0; i < 7; i++) item('d$i')]);
    expect(s.homeItems.length, 5);
    expect(s.homeItems.every((f) => f.reason == null), isTrue);
    expect(ids([for (final f in s.homeItems) f.benefit]).first, 'd0');
    expect(show([]).homeItems, isEmpty);
    final withPick = show([item('a'), item('p', featured: true)]);
    expect(withPick.homeItems.single.reason, FeaturedReason.pickedByBiso);
  });
}
