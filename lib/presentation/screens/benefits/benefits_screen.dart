import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/biso_chrome.dart';
import '../../../data/services/benefits_api_client.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/benefits/benefit_showcase.dart';
import '../../../providers/benefits/benefit_standing.dart';
import '../../../providers/benefits/benefits_providers.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../widgets/benefits/benefit_grid.dart';
import '../../widgets/benefits/benefit_perks.dart';
import '../../widgets/benefits/benefit_spotlight.dart';
import '../../widgets/benefits/benefits_top_card.dart';
import '../../widgets/biso/biso.dart';
import '../../widgets/campus/campus_switcher_sheet.dart';
import 'benefits_routes.dart';

/// On the sticky "Bli medlem" bar.
const benefitsStickyBarKey = ValueKey('benefitsStickyBar');

/// Text on the navy pill, in both themes.
const _onDeep = Colors.white;

const _stickySlide = Duration(milliseconds: 200);

/// Above this text scale the sticky bar puts its pill under the text.
const _stackPillAbove = 1.3;

/// Stands in for the campus name while the campus line is split around it.
const _namePlaceholder = '\u{FFFC}';

/// At normal text size; the text span scales it with the line.
const _chevronSize = 13.0;

const _loading = [
  SliverToBoxAdapter(child: BisoSkeleton.card()),
  SliverToBoxAdapter(child: BisoSkeleton.grid(count: 4)),
];

/// The campus the screen lists. A record, so all of BISO (`id` null) is
/// told apart from no campus yet.
typedef _Campus = ({String? id});

/// The member benefits for one campus: the top card, "Utvalgt", every deal
/// in a grid with a category filter, and "Mer enn rabatter".
///
/// Without [campusParam] the screen starts on the Home campus. With
/// [nationalCampusParam] it starts on all of BISO, and with any other value
/// on that campus id. The campus link switches this screen only: Home's
/// campus is never written.
class BenefitsScreen extends ConsumerStatefulWidget {
  const BenefitsScreen({super.key, this.campusParam});

  /// The route's `campus` query value.
  final String? campusParam;

  @override
  ConsumerState<BenefitsScreen> createState() => _BenefitsScreenState();
}

class _BenefitsScreenState extends ConsumerState<BenefitsScreen> {
  final _topCardKey = GlobalKey();

  /// Null until the campus is known: the route's, the student's pick, or
  /// the Home campus once it has loaded.
  _Campus? _campus;

  /// The category chip; null is "Alle".
  String? _category;

  /// The top card's bottom edge is above the header.
  bool _pastTopCard = false;
  bool _checkScheduled = false;
  double _headerBottom = 0;

  @override
  void initState() {
    super.initState();
    _campus = _campusOf(widget.campusParam);
  }

  @override
  void didUpdateWidget(BenefitsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.campusParam != widget.campusParam) {
      _campus = _campusOf(widget.campusParam);
      _category = null;
      _pastTopCard = false;
    }
  }

  static _Campus? _campusOf(String? param) =>
      param == null ? null : (id: campusIdFromParam(param));

  /// The Home campus, kept once it is known, so the screen stays on it.
  /// Null while Home is still finding its campus.
  _Campus? _startOnHomeCampus() {
    final home = ref.watch(filterCampusProvider.select((c) => c.id));
    // Listing all of BISO meanwhile would show the wrong campus first.
    if (home.isEmpty && !ref.watch(campusInitializedProvider)) return null;
    return _campus = (id: home.isEmpty ? null : home);
  }

  Future<void> _switchCampus(String? current) => showCampusSwitcher(
    context,
    // All of BISO is the national row in the list.
    selectedCampusId: current ?? nationalBenefitCampusId,
    onSelected: (campus) {
      final id = campus.id == nationalBenefitCampusId ? null : campus.id;
      if (!mounted || id == current) return;
      setState(() {
        _campus = (id: id);
        _category = null;
        _pastTopCard = false;
      });
    },
  );

  bool _onScroll(int depth, ScrollMetrics metrics) {
    if (depth == 0 && metrics.axis == Axis.vertical) _scheduleCheck();
    return false;
  }

  /// Checks the top card after the frame lays out the new scroll offset.
  void _scheduleCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        _checkScheduled = false;
        if (!mounted) return;
        final past = _topCardScrolledAway();
        if (past != _pastTopCard) setState(() => _pastTopCard = past);
      })
      ..ensureVisualUpdate();
  }

  bool _topCardScrolledAway() {
    final card = _topCardKey.currentContext?.findRenderObject();
    final page = context.findRenderObject();
    if (card is! RenderBox || page is! RenderBox) return false;
    if (!card.attached || !card.hasSize) return false;
    final bottom = card
        .localToGlobal(Offset(0, card.size.height), ancestor: page)
        .dy;
    return bottom <= _headerBottom;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    _headerBottom = MediaQuery.paddingOf(context).top + kBisoHeaderHeight;
    final campus = _campus ?? _startOnHomeCampus();
    if (campus == null) {
      return BisoPage(title: l10n.benefitsScreenTitle, slivers: _loading);
    }

    final campusId = campus.id;
    final name = ref.watch(benefitCampusNameProvider(campusId));
    final campusName = name.isEmpty ? l10n.benefitsAllOfBiso : name;
    final showcase = ref.watch(benefitShowcaseProvider(campusId));
    final info = ref.watch(benefitStandingProvider);
    // A retry after a failure shows the skeleton; a refresh keeps the list.
    final failed = showcase.hasError && !showcase.isLoading;
    final loaded = failed ? null : showcase.valueOrNull;
    final shown = loaded != null && !loaded.isEmpty ? loaded : null;
    final eligible = shown != null && info.isNonMember;

    final List<Widget> body;
    if (shown != null) {
      body = _sections(l10n, shown, campusId, name, info.standing);
    } else if (loaded != null || (failed && _notDeployed(showcase.error))) {
      // Nothing here, or an older API without the list: the campus line
      // stays so the student can try another campus.
      body = [
        SliverFillRemaining(
          hasScrollBody: false,
          child: BisoEmptyState(
            icon: CupertinoIcons.gift,
            title: l10n.benefitsEmpty,
          ),
        ),
      ];
    } else if (failed) {
      body = [
        SliverFillRemaining(
          hasScrollBody: false,
          child: BisoErrorState(
            onRetry: () => ref.invalidate(campusBenefitsProvider(campusId)),
          ),
        ),
      ];
    } else {
      body = _loading;
    }

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _onScroll(n.depth, n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _onScroll(n.depth, n.metrics),
        child: BisoPage(
          title: l10n.benefitsScreenTitle,
          slivers: [
            SliverToBoxAdapter(
              child: _CampusLine(
                campusName: campusName,
                onTap: () => unawaited(_switchCampus(campusId)),
              ),
            ),
            ...body,
          ],
          // Always mounted: a bar that hides reports no height, while a bar
          // taken away would leave its space behind. Never shown while
          // checking, after a failed check, or to anyone who can't join
          // from here.
          bottomBar: _StickyBar(
            eligible: eligible,
            visible: eligible && _pastTopCard,
            signedOut: info.standing == BenefitStanding.signedOut,
            countLine: shown == null
                ? ''
                : l10n.benefitsCountInCampus(shown.count, campusName),
          ),
        ),
      ),
    );
  }

  static bool _notDeployed(Object? error) =>
      error is BenefitsApiException &&
      error.kind == BenefitsApiErrorKind.notDeployed;

  /// [providerName] is `benefitCampusNameProvider`'s: empty for all of
  /// BISO, as the top card takes it.
  List<Widget> _sections(
    AppLocalizations l10n,
    BenefitShowcase showcase,
    String? campusId,
    String providerName,
    BenefitStanding standing,
  ) {
    final categories = showcase.categories;
    final filtering = categories.length > 1;
    final category = filtering && categories.contains(_category)
        ? _category
        : null;
    final deals = category == null
        ? showcase.deals
        : [
            for (final deal in showcase.deals)
              if (benefitCategoryKeyOf(deal) == category) deal,
          ];

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        sliver: SliverToBoxAdapter(
          child: BenefitsTopCard(
            key: _topCardKey,
            showcase: showcase,
            campusName: providerName,
          ),
        ),
      ),
      if (showcase.featured.isNotEmpty) ...[
        SliverToBoxAdapter(child: _SectionTitle(l10n.benefitsFeatured)),
        SliverToBoxAdapter(
          child: BenefitSpotlight(items: showcase.featured, campusId: campusId),
        ),
      ],
      if (showcase.deals.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: _SectionTitle(
            l10n.benefitsAllDeals,
            count: showcase.deals.length,
          ),
        ),
        if (filtering)
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 8),
            sliver: SliverToBoxAdapter(
              child: BenefitCategoryChips(
                categories: categories,
                selected: category,
                onSelected: (key) => setState(() => _category = key),
              ),
            ),
          ),
        benefitGridSliver(deals: deals, standing: standing, campusId: campusId),
      ],
      if (showcase.perks.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: _SectionTitle(l10n.benefitsMoreThanDiscounts),
        ),
        SliverToBoxAdapter(child: BenefitPerksSection(perks: showcase.perks)),
      ],
    ];
  }
}

/// "For BISO-medlemmer i Trondheim ⌄": the campus in BISO blue with a
/// chevron. The line is one button that opens the campus switcher.
class _CampusLine extends StatelessWidget {
  const _CampusLine({required this.campusName, required this.onTap});

  final String campusName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final palette = BisoPalette.of(context);
    final style = text.bodyMedium?.copyWith(color: palette.muted);
    final linkStyle = style?.copyWith(
      color: palette.link,
      fontWeight: FontWeight.w600,
    );
    // Wherever the translation puts the campus.
    final parts = l10n
        .benefitsCampusLine(_namePlaceholder)
        .split(_namePlaceholder);
    final before = parts.first;
    final after = parts.length > 1 ? parts.sublist(1).join() : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Semantics(
          button: true,
          label: l10n.benefitsCampusLine(campusName),
          hint: l10n.selectCampusMessage,
          onTap: onTap,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: ConstrainedBox(
              // A 44 pt tap target.
              constraints: const BoxConstraints(minHeight: 44),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: 1,
                child: Text.rich(
                  TextSpan(
                    style: style,
                    children: [
                      if (before.isNotEmpty) TextSpan(text: before),
                      TextSpan(text: campusName, style: linkStyle),
                      // The span scales the chevron with the text, once.
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(start: 2),
                          child: Icon(
                            CupertinoIcons.chevron_down,
                            size: _chevronSize,
                            color: palette.link,
                          ),
                        ),
                      ),
                      if (after.isNotEmpty) TextSpan(text: after),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A section title, with a muted count after it when there is one.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.count});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = BisoPalette.of(context);
    final count = this.count;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: text.headlineSmall?.copyWith(color: palette.ink),
                ),
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 12),
              Text(
                '$count',
                style: text.bodyMedium?.copyWith(color: palette.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Alt dette får du som medlem" on glass above the tab bar, shown once
/// the top card, with its own button, has scrolled away. It slides in and
/// out, unless the reader has asked for less motion. Hidden, it takes no
/// space and can't be seen, tapped or focused.
class _StickyBar extends StatefulWidget {
  const _StickyBar({
    required this.eligible,
    required this.visible,
    required this.signedOut,
    required this.countLine,
  });

  /// This standing and list may see the bar. When it turns false the bar
  /// goes at once, without sliding out.
  final bool eligible;

  /// Eligible, and the top card has scrolled away.
  final bool visible;
  final bool signedOut;

  /// "27 fordeler i Trondheim".
  final String countLine;

  @override
  State<_StickyBar> createState() => _StickyBarState();
}

class _StickyBarState extends State<_StickyBar>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: _stickySlide,
    value: widget.visible ? 1 : 0,
  );
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final _slide = Tween(
    begin: const Offset(0, 0.3),
    end: Offset.zero,
  ).animate(_curve);

  @override
  void didUpdateWidget(_StickyBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.eligible) {
      if (_controller.isAnimating || _controller.value != 0) {
        _controller.value = 0;
      }
    } else if (widget.visible != oldWidget.visible) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = widget.visible ? 1 : 0;
      } else if (widget.visible) {
        unawaited(_controller.forward());
      } else {
        // Reverse, not animateTo(0): only reverse ends dismissed.
        unawaited(_controller.reverse());
      }
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hidden = !widget.visible;
    final bar = FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: _slide,
        child: _Bar(
          key: benefitsStickyBarKey,
          signedOut: widget.signedOut,
          countLine: widget.countLine,
        ),
      ),
    );
    return AnimatedBuilder(
      animation: _controller,
      // Sliding out, it is already gone for taps and screen readers.
      builder: (context, child) => _controller.isDismissed
          ? const SizedBox.shrink()
          : IgnorePointer(
              ignoring: hidden,
              child: ExcludeSemantics(excluding: hidden, child: child),
            ),
      child: bar,
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({super.key, required this.signedOut, required this.countLine});

  final bool signedOut;
  final String countLine;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final palette = BisoPalette.of(context);
    final stacked =
        MediaQuery.textScalerOf(context).scale(10) > 10 * _stackPillAbove;

    final lines = MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.benefitsStickyTitle,
            style: text.titleSmall?.copyWith(color: palette.ink),
          ),
          Text(
            countLine,
            style: text.bodySmall?.copyWith(color: palette.muted),
          ),
        ],
      ),
    );
    final pill = FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: palette.deep,
        foregroundColor: _onDeep,
        // Keeps the navy pill off dark glass.
        side: BorderSide(color: palette.deepEdge),
        minimumSize: const Size(44, 40),
        padding: const EdgeInsets.symmetric(horizontal: 18),
      ),
      onPressed: signedOut
          ? () => context.go('/auth/login')
          : () => unawaited(context.push('/profile/membership')),
      child: Text(
        signedOut ? l10n.benefitsSignInAction : l10n.benefitsBecomeMember,
        textAlign: TextAlign.center,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: BisoChrome(
        radius: 20,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [lines, const SizedBox(height: 10), pill],
                )
              : Row(
                  children: [
                    Expanded(child: lines),
                    const SizedBox(width: 10),
                    pill,
                  ],
                ),
        ),
      ),
    );
  }
}
