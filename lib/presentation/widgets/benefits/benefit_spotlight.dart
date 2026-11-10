import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/benefit_highlight.dart';
import '../../../core/utils/rich_content.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/benefits/benefit_showcase.dart';
import '../../screens/benefits/benefits_routes.dart';
import '../biso/biso.dart';
import 'benefit_visuals.dart';

/// [BenefitSpotlightSize.large] is the benefits screen's "Utvalgt" carousel,
/// one card at a time. [BenefitSpotlightSize.compact] is Home's row of
/// smaller cards.
enum BenefitSpotlightSize { large, compact }

/// On the page dots under the large carousel.
const benefitSpotlightDotsKey = ValueKey('benefitSpotlightDots');

/// The least navy behind any text on a card. White over this, on a white
/// logo, reads at 4.5:1 or more.
const benefitSpotlightScrimAlpha = 0.66;

/// Text on a card, over the navy scrim in both themes.
const _onDeep = Colors.white;

/// The description's white, a step softer than the title.
final benefitSpotlightDescription = _onDeep.withValues(alpha: 0.9);

/// Navy at the very bottom of a card.
const _bottomAlpha = 0.94;

/// Where the scrim starts on a card at normal text size.
const _fadeStart = 0.3;

/// How far above the text the scrim starts to fade in, as a share of the
/// card.
const _fadeLength = 0.25;

const _viewportFraction = 0.92;
const _pageGap = 6.0;
const _compactWidth = 300.0;
const _imageCacheWidth = 900;

const _titleLines = 2;
const _descriptionLines = 2;
const _titleGap = 2.0;
const _chipGap = 8.0;

/// A reason chip: 13 pt text with 5 pt above and below.
const _chipFont = 13.0;
const _chipPadding = 10.0;
const _chipLineHeight = 1.3;

/// A carousel of picked deals. Tapping a card opens its deal page for the
/// list loaded for [campusId]. Nothing moves on its own.
class BenefitSpotlight extends StatelessWidget {
  const BenefitSpotlight({
    super.key,
    required this.items,
    required this.campusId,
    this.size = BenefitSpotlightSize.large,
  });

  final List<FeaturedBenefit> items;

  /// The campus the list was loaded for; null is all of BISO.
  final String? campusId;
  final BenefitSpotlightSize size;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final metrics = _Metrics.of(context, size);
    return switch (size) {
      BenefitSpotlightSize.large => _Pager(
        items: items,
        campusId: campusId,
        metrics: metrics,
      ),
      BenefitSpotlightSize.compact => SizedBox(
        height: metrics.height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, index) => SizedBox(
            width: _compactWidth,
            child: _SpotlightCard(
              key: ValueKey(items[index].benefit.id),
              item: items[index],
              campusId: campusId,
              metrics: metrics,
            ),
          ),
        ),
      ),
    };
  }
}

/// Sizes and type for one card size, grown with the reader's text size so
/// the chip and the text always fit.
class _Metrics {
  const _Metrics({
    required this.height,
    required this.radius,
    required this.padding,
    required this.title,
    required this.description,
    required this.value,
    required this.valueBox,
    required this.scrimStops,
  });

  factory _Metrics.of(BuildContext context, BenefitSpotlightSize size) {
    final text = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final large = size == BenefitSpotlightSize.large;

    final title = large
        ? text.titleLarge!.copyWith(color: _onDeep, height: 1.25)
        : text.titleMedium!.copyWith(
            color: _onDeep,
            fontWeight: FontWeight.w600,
            height: 1.25,
          );
    final description = (large ? text.bodyMedium! : text.bodySmall!).copyWith(
      color: benefitSpotlightDescription,
      fontSize: large ? 14 : 13,
      height: 1.3,
    );
    final value = text.displayMedium!.copyWith(
      color: _onDeep,
      fontWeight: FontWeight.w300,
      fontSize: large ? 44 : 38,
      height: 1,
    );
    final valueBox = large ? const Size(132, 56) : const Size(108, 50);
    final padding = large
        ? const EdgeInsets.fromLTRB(16, 12, 16, 14)
        : const EdgeInsets.fromLTRB(14, 10, 14, 12);
    final base = large ? 236.0 : 176.0;

    double lines(TextStyle style, int count) =>
        scaler.scale(style.fontSize!) * style.height! * count;
    final chip =
        math.max(_chipFont, scaler.scale(_chipFont) * _chipLineHeight) +
        _chipPadding;
    final textBlock = math.max(
      lines(title, _titleLines) +
          _titleGap +
          lines(description, _descriptionLines),
      valueBox.height,
    );
    final height = math.max(
      base,
      padding.top + chip + _chipGap + textBlock + padding.bottom,
    );

    // The scrim is at its least strength where the tallest text can start,
    // and fades in above that.
    final textTop = (height - padding.bottom - textBlock) / height;
    final fadeStart = math.min(
      _fadeStart,
      math.max(textTop - _fadeLength, 0.0),
    );

    return _Metrics(
      height: height,
      radius: large ? 22 : 20,
      padding: padding,
      title: title,
      description: description,
      value: value,
      valueBox: valueBox,
      scrimStops: [fadeStart, textTop, 1],
    );
  }

  final double height;
  final double radius;
  final EdgeInsets padding;
  final TextStyle title;
  final TextStyle description;
  final TextStyle value;

  /// The most room the value takes; a larger one scales down into it.
  final Size valueBox;
  final List<double> scrimStops;
}

/// The large carousel: one card at a time, with page dots under it.
class _Pager extends StatefulWidget {
  const _Pager({
    required this.items,
    required this.campusId,
    required this.metrics,
  });

  final List<FeaturedBenefit> items;
  final String? campusId;
  final _Metrics metrics;

  @override
  State<_Pager> createState() => _PagerState();
}

class _PagerState extends State<_Pager> {
  final _controller = PageController(viewportFraction: _viewportFraction);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final page = math.min(_page, items.length - 1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: widget.metrics.height,
          child: PageView.builder(
            controller: _controller,
            itemCount: items.length,
            onPageChanged: (index) => setState(() => _page = index),
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: _pageGap),
              child: _SpotlightCard(
                key: ValueKey(items[index].benefit.id),
                item: items[index],
                campusId: widget.campusId,
                metrics: widget.metrics,
              ),
            ),
          ),
        ),
        if (items.length > 1) ...[
          const SizedBox(height: 12),
          _PageDots(
            key: benefitSpotlightDotsKey,
            count: items.length,
            page: page,
          ),
        ],
      ],
    );
  }
}

/// Which card is showing. A screen reader hears the cards themselves.
class _PageDots extends StatelessWidget {
  const _PageDots({super.key, required this.count, required this.page});

  final int count;
  final int page;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Container(
              width: i == page ? 20 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == page ? palette.primary : palette.hairline,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One picked deal: its picture under a navy scrim, the reason top-left,
/// the title and description bottom-left and the value bottom-right.
class _SpotlightCard extends StatelessWidget {
  const _SpotlightCard({
    super.key,
    required this.item,
    required this.campusId,
    required this.metrics,
  });

  final FeaturedBenefit item;
  final String? campusId;
  final _Metrics metrics;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = BisoPalette.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final benefit = item.benefit;
    final reason = item.reason;
    final title = benefit.title.resolve(language) ?? '';
    final description = benefit.description.resolve(language);
    final line = description == null
        ? ''
        : richContentToPlainText(description).trim();
    final highlight = benefitHighlightOf(benefit, language);
    final value = highlight == null
        ? null
        : benefitHighlightValue(highlight, l10n);
    final m = metrics;
    final radius = BorderRadius.circular(m.radius);

    void open() => unawaited(
      context.push(
        benefitRoute(benefit.id, campusId: campusId),
        extra: benefit,
      ),
    );

    return Semantics(
      button: true,
      label: [
        if (reason != null) benefitReasonLabel(reason, benefit, l10n),
        title,
        ?value,
      ].join(', '),
      onTap: open,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            BenefitImage(
              benefit: benefit,
              memCacheWidth: _imageCacheWidth,
              fallbackNumberSize: 56,
              // The value is drawn bottom-right; once is enough.
              showHighlight: false,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    palette.deep.withValues(alpha: 0),
                    palette.deep.withValues(alpha: benefitSpotlightScrimAlpha),
                    palette.deep.withValues(alpha: _bottomAlpha),
                  ],
                  stops: m.scrimStops,
                ),
              ),
            ),
            Padding(
              padding: m.padding,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (reason != null)
                    BenefitReasonChip(reason: reason, benefit: benefit)
                  else
                    const SizedBox.shrink(),
                  Flexible(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: _titleLines,
                                overflow: TextOverflow.ellipsis,
                                style: m.title,
                              ),
                              if (line.isNotEmpty) ...[
                                const SizedBox(height: _titleGap),
                                Flexible(
                                  child: Text(
                                    line,
                                    maxLines: _descriptionLines,
                                    overflow: TextOverflow.ellipsis,
                                    style: m.description,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (value != null) ...[
                          const SizedBox(width: 12),
                          _Value(value: value, metrics: m),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Material(
              type: MaterialType.transparency,
              child: InkWell(borderRadius: radius, onTap: open),
            ),
          ],
        ),
      ),
    );
  }
}

/// "15 %" in white Museo over a short sun-yellow bar.
class _Value extends StatelessWidget {
  const _Value({required this.value, required this.metrics});

  final String value;
  final _Metrics metrics;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: metrics.valueBox.width,
        maxHeight: metrics.valueBox.height,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.bottomRight,
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(value, maxLines: 1, softWrap: false, style: metrics.value),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.only(left: 1, right: 4),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.marker,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const SizedBox(height: 5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
