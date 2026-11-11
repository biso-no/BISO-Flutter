import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/rich_content.dart';
import '../../../data/models/campus_benefit.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../biso/biso.dart';

/// The sections "Mer enn rabatter" lists, in this order. `business` never
/// shows in the app.
const _sections = [
  BenefitSection.career,
  BenefitSection.social,
  BenefitSection.safety,
];

const _tileSize = 24.0;
const _tileRadius = 6.0;
const _glyphSize = 13.0;
const _tickSize = 20.0;
const _checkSize = 13.0;

/// Room for a perk's whole title; a perk has no page of its own.
const _perkTitleLines = 4;

/// Where the rows' text starts: the tick, then the row's gap.
const _rowTextIndent = 16.0 + _tickSize + 12.0;

/// "Mer enn rabatter" under its title: for each of career, social and
/// safety that has items, a small heading and a group of ticked rows. The
/// rows can't be tapped. A box widget with its own page margins; put it in a
/// SliverToBoxAdapter.
class BenefitPerksSection extends StatelessWidget {
  const BenefitPerksSection({super.key, required this.perks});

  final Map<BenefitSection, List<CampusBenefit>> perks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final language = Localizations.localeOf(context).languageCode;
    final shown = [
      for (final section in _sections)
        if (perks[section]?.isNotEmpty ?? false) section,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, section) in shown.indexed) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(20, i == 0 ? 0 : 18, 20, 8),
            child: _Heading(section: section, l10n: l10n),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: BisoListGroup(
              dividerIndent: _rowTextIndent,
              children: [
                for (final perk in perks[section]!)
                  BisoListRow(
                    key: ValueKey(perk.id),
                    leading: const _Tick(),
                    title: perk.title.resolve(language) ?? '',
                    subtitle: _descriptionOf(perk, language),
                    titleMaxLines: _perkTitleLines,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The perk's description as plain text; null when there is none.
String? _descriptionOf(CampusBenefit perk, String language) {
  final raw = perk.description.resolve(language);
  if (raw == null) return null;
  final text = richContentToPlainText(raw).trim();
  return text.isEmpty ? null : text;
}

/// A navy tile with the section's sky glyph, and the section's name.
class _Heading extends StatelessWidget {
  const _Heading({required this.section, required this.l10n});

  final BenefitSection section;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final (icon, label) = switch (section) {
      BenefitSection.career => (
        CupertinoIcons.briefcase,
        l10n.benefitsSectionCareer,
      ),
      BenefitSection.social => (
        CupertinoIcons.person_2,
        l10n.benefitsSectionSocial,
      ),
      _ => (CupertinoIcons.shield, l10n.benefitsSectionSafety),
    };
    return Row(
      children: [
        ExcludeSemantics(
          child: SizedBox.square(
            dimension: _tileSize,
            child: DecoratedBox(
              // The edge keeps the navy off the dark paper in dark mode.
              decoration: BoxDecoration(
                color: palette.deep,
                borderRadius: BorderRadius.circular(_tileRadius),
                border: Border.all(color: palette.deepEdge),
              ),
              child: Icon(icon, size: _glyphSize, color: palette.sky),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: palette.muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A sky circle with a navy check.
class _Tick extends StatelessWidget {
  const _Tick();

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: _tickSize,
        child: DecoratedBox(
          decoration: BoxDecoration(color: palette.sky, shape: BoxShape.circle),
          child: Icon(
            CupertinoIcons.checkmark,
            size: _checkSize,
            color: palette.deep,
          ),
        ),
      ),
    );
  }
}
