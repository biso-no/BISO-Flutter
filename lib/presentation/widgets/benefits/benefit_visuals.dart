import 'package:biso/core/theme/biso_colors.dart';
import 'package:biso/core/utils/benefit_highlight.dart';
import 'package:biso/core/utils/oslo_time.dart';
import 'package:biso/data/models/campus_benefit.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/providers/benefits/benefit_showcase.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const _nbsp = ' ';

/// The icon for a benefit category key; unknown keys read as "other".
IconData benefitCategoryIcon(String key) => switch (key) {
  'food_drink' => Icons.restaurant, // biso:allow no Cupertino food icon
  'health_fitness' => CupertinoIcons.sportscourt,
  'nightlife' => CupertinoIcons.moon_stars,
  'shopping' => CupertinoIcons.bag,
  'travel' => CupertinoIcons.airplane,
  'software' => CupertinoIcons.device_laptop,
  'events' => CupertinoIcons.calendar,
  _ => CupertinoIcons.sparkles,
};

String benefitCategoryLabel(String key, AppLocalizations l10n) => switch (key) {
  'food_drink' => l10n.benefitsCategoryFoodDrink,
  'health_fitness' => l10n.benefitsCategoryHealthFitness,
  'nightlife' => l10n.benefitsCategoryNightlife,
  'shopping' => l10n.benefitsCategoryShopping,
  'travel' => l10n.benefitsCategoryTravel,
  'software' => l10n.benefitsCategorySoftware,
  'events' => l10n.benefitsCategoryEvents,
  _ => l10n.benefitsCategoryOther,
};

/// Short text for a badge: "−25 %", "Gratis", "150 kr".
String benefitHighlightBadge(BenefitHighlight h, AppLocalizations l10n) =>
    switch (h.kind) {
      BenefitHighlightKind.percent => '−${h.amount}$_nbsp%',
      BenefitHighlightKind.free => l10n.benefitsFree,
      BenefitHighlightKind.price => '${h.amount}${_nbsp}kr',
    };

/// The value on its own: "25 %", "Gratis", "150 kr".
String benefitHighlightValue(BenefitHighlight h, AppLocalizations l10n) =>
    switch (h.kind) {
      BenefitHighlightKind.percent => '${h.amount}$_nbsp%',
      BenefitHighlightKind.free => l10n.benefitsFree,
      BenefitHighlightKind.price => '${h.amount}${_nbsp}kr',
    };

String benefitReasonLabel(
  FeaturedReason r,
  CampusBenefit b,
  AppLocalizations l10n,
) {
  switch (r) {
    case FeaturedReason.pickedByBiso:
      return l10n.benefitsReasonPicked;
    case FeaturedReason.isNew:
      return l10n.benefitsReasonNew;
    case FeaturedReason.endingSoon:
      final end = b.publishEnd;
      if (end == null) return l10n.benefitsReasonPicked;
      final date = DateFormat(
        'd. MMM',
        l10n.localeName,
      ).format(osloCalendarDay(end));
      return l10n.benefitsReasonEnds(date);
  }
}

IconData benefitReasonIcon(FeaturedReason r) => switch (r) {
  FeaturedReason.pickedByBiso => CupertinoIcons.star_fill,
  FeaturedReason.endingSoon => CupertinoIcons.clock,
  FeaturedReason.isNew => CupertinoIcons.sparkles,
};

/// A benefit's image, filling its parent. Without an image, or when it fails
/// to load, a navy panel shows the discount or the category icon.
class BenefitImage extends StatelessWidget {
  const BenefitImage({
    required this.benefit,
    required this.memCacheWidth,
    this.fallbackNumberSize = 44,
    super.key,
  });

  final CampusBenefit benefit;
  final int memCacheWidth;
  final double fallbackNumberSize;

  @override
  Widget build(BuildContext context) {
    final url = benefit.imageUrl;
    return ExcludeSemantics(
      child: url == null || url.isEmpty
          ? _fallback(context)
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              memCacheWidth: memCacheWidth,
              errorWidget: (context, _, _) => _fallback(context),
            ),
    );
  }

  Widget _fallback(BuildContext context) {
    final palette = BisoPalette.of(context);
    final l10n = AppLocalizations.of(context)!;
    final highlight = benefitHighlightOf(benefit, l10n.localeName);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.deep, palette.deepRaised],
        ),
      ),
      child: Center(
        child: highlight == null
            ? Icon(
                benefitCategoryIcon(benefitCategoryKeyOf(benefit)),
                color: palette.sky,
                size: fallbackNumberSize,
              )
            : Padding(
                padding: const EdgeInsets.all(8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    benefitHighlightValue(highlight, l10n),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: palette.sky,
                      fontSize: fallbackNumberSize,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// A small yellow badge for a deal's discount.
class BenefitBadge extends StatelessWidget {
  const BenefitBadge(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.marker,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            color: palette.deep,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Why a deal is among the picks, as a chip with an icon.
class BenefitReasonChip extends StatelessWidget {
  const BenefitReasonChip({
    required this.reason,
    required this.benefit,
    this.onImage = true,
    super.key,
  });

  final FeaturedReason reason;
  final CampusBenefit benefit;

  /// True on a photo or navy panel, false on a plain surface.
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final l10n = AppLocalizations.of(context)!;
    final foreground = onImage ? palette.deepMuted : palette.muted;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: onImage ? palette.deep : palette.surfaceRaised,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              benefitReasonIcon(reason),
              size: 13,
              color: onImage ? palette.sky : palette.link,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                benefitReasonLabel(reason, benefit, l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
