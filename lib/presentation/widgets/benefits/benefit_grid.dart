import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/benefit_highlight.dart';
import '../../../core/utils/rich_content.dart';
import '../../../data/models/campus_benefit.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/benefits/benefit_standing.dart';
import '../../screens/benefits/benefits_routes.dart';
import '../biso/biso.dart';
import 'benefit_visuals.dart';

/// White text on the navy selected chip, in both themes.
const _onDeep = Colors.white;

const _pageMargin = 16.0;
const _gridGap = 12.0;
const _cardRadius = 18.0;
const _imageAspect = 4 / 3;
const _imageCacheWidth = 600;
const _badgeInset = 10.0;

/// Long enough for a 70-character title at normal text size; larger text
/// ends it with an ellipsis. The deal page has the whole title.
const _titleLines = 4;
const _descriptionLines = 2;
const _claimIconSize = 13.0;

const _chipGap = 12.0;
const _chipHeight = 34.0;
const _chipIconSize = 16.0;

/// Room above and below a chip so the tap target is 44 pt tall.
const _chipTapPadding = 5.0;

/// Every deal in [deals], two cards to a row in the order given. A row is as
/// tall as its taller card, and grows with the reader's text size.
Widget benefitGridSliver({
  required List<CampusBenefit> deals,
  required BenefitStanding standing,
  required String? campusId,
}) {
  Widget card(CampusBenefit b) => BenefitGridCard(
    key: ValueKey(b.id),
    benefit: b,
    standing: standing,
    campusId: campusId,
  );

  return SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: _pageMargin),
    sliver: SliverList.builder(
      itemCount: (deals.length + 1) ~/ 2,
      itemBuilder: (context, row) {
        final left = row * 2;
        final right = left + 1;
        return Padding(
          padding: EdgeInsets.only(top: row == 0 ? 0 : _gridGap),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: card(deals[left])),
                const SizedBox(width: _gridGap),
                Expanded(
                  child: right < deals.length
                      ? card(deals[right])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// How a deal is claimed, as the card's bottom line says it.
typedef _Claim = ({IconData? icon, String label});

/// Non-members and signed-out students read "Bare for medlemmer" on every
/// card. Everyone else, including while the standing is still being checked,
/// reads how the deal is claimed, which says nothing about the viewer.
_Claim? _claimOf(
  CampusBenefit b,
  BenefitStanding standing,
  AppLocalizations l10n,
) {
  final locked =
      standing == BenefitStanding.notMember ||
      standing == BenefitStanding.signedOut;
  if (locked) {
    return (icon: CupertinoIcons.lock, label: l10n.benefitsMembersOnlyShort);
  }
  return switch (b.redemptionType) {
    BenefitRedemptionType.onsite => (
      icon: CupertinoIcons.creditcard,
      label: l10n.benefitsClaimCard,
    ),
    BenefitRedemptionType.code => (icon: null, label: l10n.benefitsClaimCode),
    BenefitRedemptionType.link => (icon: null, label: l10n.benefitsClaimLink),
    BenefitRedemptionType.none => null,
  };
}

/// One deal in "Alle tilbud": its picture with the discount badge, the
/// title, two lines of description and how it is claimed. Tapping opens the
/// deal page for the list loaded for [campusId].
class BenefitGridCard extends StatelessWidget {
  const BenefitGridCard({
    super.key,
    required this.benefit,
    required this.standing,
    required this.campusId,
  });

  final CampusBenefit benefit;
  final BenefitStanding standing;

  /// The campus the list was loaded for; null is all of BISO.
  final String? campusId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    final language = Localizations.localeOf(context).languageCode;
    final title = benefit.title.resolve(language) ?? '';
    final description = benefit.description.resolve(language);
    final line = description == null
        ? ''
        : richContentToPlainText(description).trim();
    final highlight = benefitHighlightOf(benefit, language);
    final badge = highlight == null
        ? null
        : benefitHighlightBadge(highlight, l10n);
    // Read as "25 %", not the badge's "minus 25 %".
    final value = highlight == null
        ? null
        : benefitHighlightValue(highlight, l10n);
    final hasImage = benefit.imageUrl?.isNotEmpty ?? false;
    final claim = _claimOf(benefit, standing, l10n);
    final radius = BorderRadius.circular(_cardRadius);

    void open() => unawaited(
      context.push(
        benefitRoute(benefit.id, campusId: campusId),
        extra: benefit,
      ),
    );

    return Semantics(
      button: true,
      label: [title, ?value, ?claim?.label].join(', '),
      onTap: open,
      excludeSemantics: true,
      child: Material(
        color: palette.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: _imageAspect,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Without a picture the navy tile shows the
                          // number; with one the badge does, so a picture
                          // that fails to load falls back to the icon.
                          BenefitImage(
                            benefit: benefit,
                            memCacheWidth: _imageCacheWidth,
                            showHighlight: !hasImage,
                          ),
                          if (badge != null && hasImage)
                            Padding(
                              padding: const EdgeInsets.all(_badgeInset),
                              child: Align(
                                alignment: AlignmentDirectional.topStart,
                                child: BenefitBadge(badge),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        10,
                        12,
                        claim == null ? 12 : 0,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: _titleLines,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleSmall?.copyWith(
                              color: palette.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                          if (line.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              line,
                              maxLines: _descriptionLines,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall?.copyWith(
                                color: palette.muted,
                                fontSize: 13,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                // Pinned to the bottom, so the claim lines in a row line up.
                if (claim != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
                    child: _ClaimLine(claim: claim),
                  ),
              ],
            ),
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(borderRadius: radius, onTap: open),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClaimLine extends StatelessWidget {
  const _ClaimLine({required this.claim});

  final _Claim claim;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final icon = claim.icon;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: _claimIconSize, color: palette.muted),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            claim.label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: palette.muted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// The category filter above the grid: "Alle" (null), then one chip per key
/// in [categories], in the order given. Shows nothing for fewer than two
/// categories, where there is nothing to filter.
class BenefitCategoryChips extends StatelessWidget {
  const BenefitCategoryChips({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  /// Catalogue keys, such as `food_drink`.
  final List<String> categories;

  /// The selected key; null is "Alle".
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    if (categories.length < 2) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: _pageMargin),
      child: Row(
        children: [
          _CategoryChip(
            label: l10n.benefitsCategoryAll,
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final key in categories) ...[
            const SizedBox(width: _chipGap),
            _CategoryChip(
              icon: benefitCategoryIcon(key),
              label: benefitCategoryLabel(key, l10n),
              selected: selected == key,
              onTap: () => onSelected(key),
            ),
          ],
        ],
      ),
    );
  }
}

/// A rounded chip, the shape of [BenefitPill]: navy with white text when
/// selected, otherwise the surface with a hairline. 44 pt tall to tap.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final IconData? icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final foreground = selected ? _onDeep : palette.ink;
    final icon = this.icon;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: _chipTapPadding),
          child: DecoratedBox(
            // The navy chip's edge keeps it off the dark paper in dark mode.
            decoration: BoxDecoration(
              color: selected ? palette.deep : palette.surface,
              border: Border.all(
                color: selected ? palette.deepEdge : palette.hairline,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _chipHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: _chipIconSize, color: foreground),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      label,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
