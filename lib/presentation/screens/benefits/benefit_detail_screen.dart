import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/benefit_highlight.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../core/utils/oslo_time.dart';
import '../../../core/utils/rich_content.dart';
import '../../../data/models/campus_benefit.dart';
import '../../../data/services/benefits_api_client.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/benefits/benefit_showcase.dart';
import '../../../providers/benefits/benefits_providers.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../widgets/benefits/benefit_action_panel.dart';
import '../../widgets/benefits/benefit_visuals.dart';
import '../../widgets/biso/biso.dart';
import '../../widgets/premium/premium_html_renderer.dart';
import 'benefits_routes.dart';

const _imageHeight = 300.0;
const _gutter = 20.0;
const _moreLimit = 8;
const _moreSize = 140.0;

const _loading = SliverPadding(
  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
  sliver: SliverToBoxAdapter(child: BisoSkeleton.card()),
);

/// Back to the benefits list for [campusParam], also after a cold link.
BisoBackButton _backTo(BuildContext context, String? campusParam) =>
    BisoBackButton(
      onPressed: () => NavigationUtils.safeGoBack(
        context,
        fallbackRoute: benefitsRoute(campusParam: campusParam),
      ),
    );

/// `/:benefitId` under `/explore/benefits`.
///
/// `?campus=` names the list the deal was opened from, [nationalCampusParam]
/// for all of BISO. A bare link from outside the app uses the Home campus,
/// whose list holds the all-of-BISO deals too.
GoRoute benefitDetailRoute() => GoRoute(
  path: '/:benefitId',
  name: 'benefit-detail',
  builder: (context, state) {
    final extra = state.extra;
    return _BenefitDetailRoute(
      benefitId: state.pathParameters['benefitId']!,
      campusParam: state.uri.queryParameters['campus'],
      initial: extra is CampusBenefit ? extra : null,
    );
  },
);

class _BenefitDetailRoute extends ConsumerWidget {
  const _BenefitDetailRoute({
    required this.benefitId,
    required this.campusParam,
    required this.initial,
  });

  final String benefitId;
  final String? campusParam;
  final CampusBenefit? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final param = campusParam;
    if (param != null) {
      return BenefitDetailScreen(
        benefitId: benefitId,
        campusId: campusIdFromParam(param),
        initial: initial,
      );
    }
    final home = ref.watch(filterCampusProvider.select((c) => c.id));
    // Looking in the all-of-BISO list meanwhile could call a campus deal
    // gone, so wait for the Home campus.
    if (home.isEmpty && !ref.watch(campusInitializedProvider)) {
      return BisoPage(
        largeTitle: false,
        leading: _backTo(context, null),
        slivers: const [_loading],
      );
    }
    return BenefitDetailScreen(
      benefitId: benefitId,
      campusId: home.isEmpty ? null : home,
      initial: initial,
    );
  }
}

/// One deal, opened from the benefits screen, Home, the member pass or a
/// link.
///
/// [initial] is the deal as a list already has it, so the page draws at
/// once. Without it the page looks [benefitId] up in the list for
/// [campusId]. Either way it watches that list, the one the benefits screen
/// shares, for the Utvalgt reason, the campus count and "Mer innen".
class BenefitDetailScreen extends ConsumerWidget {
  const BenefitDetailScreen({
    super.key,
    required this.benefitId,
    required this.campusId,
    this.initial,
  });

  final String benefitId;

  /// The campus the list was loaded for; null is all of BISO.
  final String? campusId;
  final CampusBenefit? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showcase = ref.watch(benefitShowcaseProvider(campusId));
    final loaded = showcase.valueOrNull;
    final benefit = _find(loaded, benefitId) ?? initial;
    final back = _backTo(context, pinnedCampusParam(campusId));

    if (benefit == null) {
      return BisoPage(
        largeTitle: false,
        leading: back,
        slivers: [_missing(context, ref, showcase)],
      );
    }

    final language = Localizations.localeOf(context).languageCode;
    final category = benefitCategoryKeyOf(benefit);
    final more = loaded == null
        ? const <CampusBenefit>[]
        : [
            for (final deal in loaded.deals)
              if (deal.id != benefit.id &&
                  benefitCategoryKeyOf(deal) == category)
                deal,
          ].take(_moreLimit).toList();

    return BisoPage(
      overImage: true,
      largeTitle: false,
      title: benefit.title.resolve(language) ?? '',
      leading: back,
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: _imageHeight,
            width: double.infinity,
            child: BenefitImage(
              benefit: benefit,
              memCacheWidth: 1080,
              fallbackNumberSize: 64,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(_gutter, 18, _gutter, 0),
          sliver: SliverToBoxAdapter(
            child: _DealBody(
              benefit: benefit,
              campusId: campusId,
              showcase: loaded,
            ),
          ),
        ),
        if (more.isNotEmpty)
          SliverToBoxAdapter(
            child: _MoreInCategory(
              categoryKey: category,
              deals: more,
              campusId: campusId,
            ),
          ),
      ],
    );
  }

  /// No deal to draw: still loading, failed, or gone.
  Widget _missing(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<BenefitShowcase> showcase,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final gone = SliverFillRemaining(
      hasScrollBody: false,
      child: BisoEmptyState(
        icon: CupertinoIcons.gift,
        title: l10n.benefitsNotFound,
      ),
    );
    return showcase.when(
      loading: () => _loading,
      error: (error, _) {
        // An older API without the route can never find it.
        if (error is BenefitsApiException &&
            error.kind == BenefitsApiErrorKind.notDeployed) {
          return gone;
        }
        return SliverFillRemaining(
          hasScrollBody: false,
          child: BisoErrorState(
            onRetry: () => ref.invalidate(campusBenefitsProvider(campusId)),
          ),
        );
      },
      data: (_) => gone,
    );
  }
}

/// [id] among the deals and perks of [showcase], or null.
CampusBenefit? _find(BenefitShowcase? showcase, String id) {
  if (showcase == null) return null;
  for (final b in showcase.deals) {
    if (b.id == id) return b;
  }
  for (final list in showcase.perks.values) {
    for (final b in list) {
      if (b.id == id) return b;
    }
  }
  return null;
}

/// The Utvalgt reason for [benefit], if it is among the picks.
FeaturedReason? _reasonOf(BenefitShowcase? showcase, CampusBenefit benefit) {
  for (final f in showcase?.featured ?? const <FeaturedBenefit>[]) {
    if (f.benefit.id == benefit.id) return f.reason;
  }
  return null;
}

/// Everything under the picture, down to the info group.
class _DealBody extends ConsumerWidget {
  const _DealBody({
    required this.benefit,
    required this.campusId,
    required this.showcase,
  });

  final CampusBenefit benefit;
  final String? campusId;

  /// The campus list, once it has loaded.
  final BenefitShowcase? showcase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final palette = BisoPalette.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final highlight = benefitHighlightOf(benefit, language);
    final description = benefit.description.resolve(language);
    final campusName = ref.watch(benefitCampusNameProvider(campusId));
    final loaded = showcase;
    // Until the list is in, the locked text leaves the count out.
    final otherCount = loaded == null ? 0 : math.max(loaded.count - 1, 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Chips(benefit: benefit, reason: _reasonOf(showcase, benefit)),
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text(
            benefit.title.resolve(language) ?? '',
            style: text.headlineSmall?.copyWith(
              fontSize: 26,
              color: palette.ink,
            ),
          ),
        ),
        const SizedBox(height: 6),
        _Where(benefit: benefit),
        if (highlight != null) ...[
          const SizedBox(height: 16),
          _Highlight(highlight: highlight),
        ],
        const SizedBox(height: 20),
        BenefitActionPanel(
          // The panel holds a revealed code; keep it with this deal.
          key: ValueKey(benefit.id),
          benefit: benefit,
          otherCount: otherCount,
          campusName: campusName.isEmpty ? l10n.benefitsAllOfBiso : campusName,
        ),
        if (description != null) ...[
          _Heading(l10n.benefitsAboutDeal),
          // Stored as HTML, Plate JSON or plain text.
          description.toFullHtml(
            style: text.bodyLarge?.copyWith(color: palette.ink),
            fontSize: text.bodyLarge?.fontSize,
          ),
        ],
        const SizedBox(height: 24),
        _InfoGroup(benefit: benefit),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 10),
    child: Semantics(
      header: true,
      child: Text(
        title,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontSize: 20,
          color: BisoPalette.of(context).ink,
        ),
      ),
    ),
  );
}

/// The category, and the Utvalgt reason when the deal is among the picks.
class _Chips extends StatelessWidget {
  const _Chips({required this.benefit, required this.reason});

  final CampusBenefit benefit;
  final FeaturedReason? reason;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = BisoPalette.of(context);
    final key = benefitCategoryKeyOf(benefit);
    final reason = this.reason;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        BenefitPill(
          icon: benefitCategoryIcon(key),
          label: benefitCategoryLabel(key, l10n),
          background: palette.surfaceRaised,
          foreground: palette.ink,
        ),
        if (reason != null)
          BenefitReasonChip(reason: reason, benefit: benefit, onImage: false),
      ],
    );
  }
}

/// Who gives the deal: the partner, else the campus with a pin.
class _Where extends ConsumerWidget {
  const _Where({required this.benefit});

  static const double _logoSize = 22;

  final CampusBenefit benefit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final palette = BisoPalette.of(context);
    final partner = benefit.partner;
    final style = text.bodyMedium?.copyWith(color: palette.muted);

    Widget? lead;
    final String label;
    if (partner != null) {
      label = partner.name;
      final logo = partner.logoUrl;
      if (logo != null) {
        lead = ExcludeSemantics(
          child: Container(
            width: _logoSize,
            height: _logoSize,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: palette.hairline),
            ),
            child: CachedNetworkImage(
              imageUrl: logo,
              fit: BoxFit.cover,
              memCacheWidth: 96,
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        );
      }
    } else {
      final name = ref.watch(benefitCampusNameProvider(benefit.campusId));
      label = name.isEmpty ? l10n.benefitsAllOfBiso : name;
      lead = Icon(
        CupertinoIcons.location_solid,
        size: 15,
        color: palette.muted,
      );
    }

    return Row(
      children: [
        if (lead != null) ...[lead, const SizedBox(width: 8)],
        Flexible(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}

/// The deal in large type: "25 %" over a sun-yellow bar, and "rabatt for
/// medlemmer" beside it for a percentage.
class _Highlight extends StatelessWidget {
  const _Highlight({required this.highlight});

  final BenefitHighlight highlight;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final palette = BisoPalette.of(context);
    final percent = highlight.kind == BenefitHighlightKind.percent;
    return MergeSemantics(
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    benefitHighlightValue(highlight, l10n),
                    style: text.displayMedium?.copyWith(
                      // Navy on light paper, sky on dark: never navy on navy.
                      color: palette.primary,
                      fontWeight: FontWeight.w300,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 2, right: 6),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.marker,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const SizedBox(height: 6),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (percent)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                l10n.benefitsDiscountForMembers,
                style: text.bodyLarge?.copyWith(color: palette.ink),
              ),
            ),
        ],
      ),
    );
  }
}

/// Gyldig, Nettside and Vilkår.
class _InfoGroup extends ConsumerWidget {
  const _InfoGroup({required this.benefit});

  final CampusBenefit benefit;

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    Uri uri,
    AppLocalizations l10n,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await ref.read(benefitLinkOpenerProvider)(uri);
    } on Object {
      opened = false;
    }
    if (opened) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.benefitsLinkFailed)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final language = Localizations.localeOf(context).languageCode;
    final end = benefit.publishEnd;
    final website = benefitHttpsUri(benefit.partner?.websiteUrl);
    final terms = benefit.terms.resolve(language);
    return BisoListGroup(
      children: [
        BisoListRow(
          leading: const BisoIconTile(icon: CupertinoIcons.clock),
          title: l10n.benefitsValid,
          value: end == null
              ? l10n.benefitsUntilFurther
              : l10n.benefitsUntilDate(formatOsloDate(end, l10n.localeName)),
        ),
        if (website != null)
          BisoListRow(
            leading: const BisoIconTile(icon: CupertinoIcons.globe),
            title: l10n.benefitsWebsite,
            value: _displayHost(website),
            valueColor: BisoPalette.of(context).link,
            onTap: () => unawaited(_open(context, ref, website, l10n)),
          ),
        if (terms != null) _TermsRow(title: l10n.benefitsTerms, terms: terms),
      ],
    );
  }
}

/// "www.graffi.no/meny" reads as "graffi.no".
String _displayHost(Uri uri) =>
    uri.host.startsWith('www.') ? uri.host.substring(4) : uri.host;

/// "Vilkår": a row that folds the terms open and closed.
class _TermsRow extends StatefulWidget {
  const _TermsRow({required this.title, required this.terms});

  final String title;
  final String terms;

  @override
  State<_TermsRow> createState() => _TermsRowState();
}

class _TermsRowState extends State<_TermsRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = BisoPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: Semantics(
            expanded: _open,
            child: BisoListRow(
              leading: const BisoIconTile(icon: CupertinoIcons.doc_text),
              title: widget.title,
              trailing: Icon(
                _open ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
                size: 17,
                color: palette.muted,
              ),
              onTap: () => setState(() => _open = !_open),
            ),
          ),
        ),
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
          alignment: Alignment.topLeft,
          child: _open
              ? Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(60, 0, 16, 14),
                  child: widget.terms.toFullHtml(
                    style: text.bodyMedium?.copyWith(color: palette.muted),
                    fontSize: text.bodyMedium?.fontSize,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// "Mer innen {kategori}": other deals of the same category, side by side.
class _MoreInCategory extends StatelessWidget {
  const _MoreInCategory({
    required this.categoryKey,
    required this.deals,
    required this.campusId,
  });

  final String categoryKey;
  final List<CampusBenefit> deals;
  final String? campusId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final label = benefitCategoryLabel(categoryKey, l10n);
    // Mid-sentence in Norwegian: "Mer innen mat og drikke".
    final english = Localizations.localeOf(context).languageCode == 'en';
    final category = english ? label : label.toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _gutter),
          child: _Heading(l10n.benefitsMoreInCategory(category)),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: _gutter),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < deals.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                _MoreCard(benefit: deals[i], campusId: campusId),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A square picture with the discount badge, the title and one line.
class _MoreCard extends StatelessWidget {
  const _MoreCard({required this.benefit, required this.campusId});

  final CampusBenefit benefit;
  final String? campusId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final palette = BisoPalette.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final highlight = benefitHighlightOf(benefit, language);
    final description = benefit.description.resolve(language);
    final line = description == null
        ? null
        : richContentToPlainText(description).trim();
    final radius = BorderRadius.circular(18);
    final title = benefit.title.resolve(language) ?? '';
    void open() => unawaited(
      context.push(
        benefitRoute(benefit.id, campusId: campusId),
        extra: benefit,
      ),
    );

    return SizedBox(
      width: _moreSize,
      // One button, read as its title and the deal: "GoBowl, 15 %".
      child: Semantics(
        button: true,
        label: [
          title,
          if (highlight != null) benefitHighlightValue(highlight, l10n),
        ].join(', '),
        onTap: open,
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: open,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: radius,
                  child: SizedBox.square(
                    dimension: _moreSize,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        BenefitImage(benefit: benefit, memCacheWidth: 420),
                        if (highlight != null)
                          Positioned(
                            left: 8,
                            top: 8,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: _moreSize - 16,
                              ),
                              child: BenefitBadge(
                                benefitHighlightBadge(highlight, l10n),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(color: palette.ink),
                  ),
                ),
                if (line != null && line.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 1, 2, 0),
                    child: Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: palette.muted),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
