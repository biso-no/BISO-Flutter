import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/oslo_time.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/benefits/benefit_showcase.dart';
import '../../../providers/benefits/benefit_standing.dart';
import '../../screens/auth/continue_with_bi_action.dart';
import '../../screens/profile/member_pass_presentation.dart';
import '../biso/biso.dart';

/// Text on the navy card, which stays navy in both themes.
const _onDeep = Colors.white;

const _maxLogos = 5;
const _logoSize = 40.0;
const _logoOverlap = 10.0;

/// 40 pt at 3x.
const _logoCacheWidth = 120;

/// Above this text scale the member row puts its pill under the text.
const _stackPillAbove = 1.3;

/// The navy card at the top of the benefits screen: how many benefits there
/// are, a row of partner images, and what the student can do next.
///
/// The action row follows [benefitStandingProvider]. While the membership
/// is being checked, or the check failed, the card shows only the count and
/// a neutral line, so it never reads as "not a member".
class BenefitsTopCard extends ConsumerWidget {
  const BenefitsTopCard({
    super.key,
    required this.showcase,
    required this.campusName,
  });

  final BenefitShowcase showcase;

  /// From `benefitCampusNameProvider`; empty for all of BISO.
  final String campusName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final palette = BisoPalette.of(context);
    final info = ref.watch(benefitStandingProvider);
    final count = showcase.count;
    final campus = campusName.isEmpty ? l10n.benefitsAllOfBiso : campusName;
    final lead = switch (info.standing) {
      BenefitStanding.member ||
      BenefitStanding.upcoming => l10n.benefitsTopMember(count, campus),
      BenefitStanding.notMember ||
      BenefitStanding.signedOut => l10n.benefitsTopNonMember(count, campus),
      BenefitStanding.needsBi ||
      BenefitStanding.checking ||
      BenefitStanding.unavailable => l10n.benefitsTopNeutral(count, campus),
    };
    final images = showcase.imageUrls;
    final radius = BorderRadius.circular(24);

    return DecoratedBox(
      // Above the ring. Only shows against dark paper, where the card would
      // otherwise sink in.
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: palette.deepEdge),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: ColoredBox(
          color: palette.deep,
          child: Stack(
            children: [
              Positioned(
                right: -54,
                top: -54,
                child: ExcludeSemantics(
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: palette.sky.withValues(alpha: 0.16),
                        width: 30,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 39,
                top: 37,
                child: ExcludeSemantics(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.marker,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MergeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$count',
                            style: text.displayLarge?.copyWith(
                              color: palette.sky,
                              fontWeight: FontWeight.w300,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 280),
                            child: Text(
                              lead,
                              style: text.bodyLarge?.copyWith(
                                color: _onDeep.withValues(alpha: 0.92),
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (images.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _Logos(urls: images),
                    ],
                    // Mounted for every standing, so a BI sign-in that
                    // reloads the pass still finishes.
                    _ActionArea(info: info, gap: images.isEmpty ? 16 : 18),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the student can do next, under [gap]. Empty while checking or after
/// a failed check.
///
/// It stays mounted whatever the standing, like `BenefitActionPanel`: a BI
/// sign-in into another account reloads the pass (the standing goes through
/// checking), and the flow, with its onboarding step and message, has to
/// finish all the same.
class _ActionArea extends ConsumerStatefulWidget {
  const _ActionArea({required this.info, required this.gap});

  final BenefitStandingInfo info;
  final double gap;

  @override
  ConsumerState<_ActionArea> createState() => _ActionAreaState();
}

class _ActionAreaState extends ConsumerState<_ActionArea> {
  /// A BI sync or sign-in is running.
  bool _biBusy = false;

  Future<void> _continueWithBi() async {
    // One flow at a time, however fast the taps come.
    if (_biBusy) return;
    setState(() => _biBusy = true);
    try {
      await runContinueWithBi(context, ref);
    } finally {
      if (mounted) setState(() => _biBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final action = _action(l10n, widget.info);
    if (action == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: widget.gap),
      child: action,
    );
  }

  Widget? _action(AppLocalizations l10n, BenefitStandingInfo info) {
    switch (info.standing) {
      case BenefitStanding.notMember:
        return _SkyPill(
          label: l10n.benefitsBecomeMember,
          onPressed: () => unawaited(context.push('/profile/membership')),
        );
      case BenefitStanding.signedOut:
        return _SkyPill(
          label: l10n.benefitsSignInAction,
          onPressed: () => context.go('/auth/login'),
        );
      case BenefitStanding.member:
        final until = info.validUntil;
        return _StandingRow(
          tile: const _Seal(),
          title: l10n.benefitsYouAreMember,
          subtitle: until == null
              ? null
              : l10n.benefitsMemberValidUntil(
                  formatOsloDate(until, l10n.localeName),
                ),
          action: _ShowCardPill(
            label: l10n.benefitsShowCardShort,
            onPressed: () => unawaited(showPassPresentation(context)),
          ),
        );
      case BenefitStanding.upcoming:
        final start = info.upcomingStart;
        if (start == null) return null;
        return _StandingRow(
          tile: const _Seal(),
          title: l10n.membershipStartsOn(
            formatOsloDate(start, l10n.localeName),
          ),
        );
      case BenefitStanding.needsBi:
        return _StandingRow(
          tile: const _GlyphTile(icon: CupertinoIcons.person_crop_rectangle),
          title: l10n.membershipNeedsBiLinkTitle,
          stackAction: true,
          action: _SkyPill(
            label: l10n.membershipNeedsBiLinkCta,
            compact: true,
            onPressed: _biBusy ? null : () => unawaited(_continueWithBi()),
          ),
        );
      case BenefitStanding.checking || BenefitStanding.unavailable:
        return null;
    }
  }
}

/// Up to five round partner images, overlapping, then "+ N til".
class _Logos extends StatelessWidget {
  const _Logos({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = BisoPalette.of(context);
    final shown = urls.take(_maxLogos).toList();
    final more = urls.length - shown.length;
    const step = _logoSize - _logoOverlap;
    // The count above says it already; the faces are decoration.
    return ExcludeSemantics(
      child: Row(
        children: [
          SizedBox(
            width: step * (shown.length - 1) + _logoSize,
            height: _logoSize,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < shown.length; i++)
                  Positioned(
                    left: step * i,
                    top: 0,
                    child: _Logo(url: shown[i]),
                  ),
              ],
            ),
          ),
          if (more > 0) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                l10n.benefitsMoreLogos(more),
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: palette.deepMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    return Container(
      width: _logoSize,
      height: _logoSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Logos are often drawn for white.
        color: _onDeep,
        border: Border.all(
          color: palette.deep,
          width: 3,
          strokeAlign: BorderSide.strokeAlignOutside,
        ),
      ),
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          memCacheWidth: _logoCacheWidth,
          errorWidget: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// A sky pill with navy text, for the navy card.
class _SkyPill extends StatelessWidget {
  const _SkyPill({
    required this.label,
    required this.onPressed,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Inside a row: a little shorter.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: palette.sky,
        foregroundColor: palette.deep,
        disabledBackgroundColor: palette.sky.withValues(alpha: 0.5),
        disabledForegroundColor: palette.deep,
        minimumSize: Size(44, compact ? 40 : 46),
        padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 22),
      ),
      onPressed: onPressed,
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}

/// "Vis kort": a white pill with a card icon.
class _ShowCardPill extends StatelessWidget {
  const _ShowCardPill({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: _onDeep,
        foregroundColor: palette.deep,
        minimumSize: const Size(44, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        textStyle: Theme.of(context).textTheme.titleSmall,
      ),
      onPressed: onPressed,
      icon: const Icon(CupertinoIcons.creditcard, size: 16),
      label: Text(label),
    );
  }
}

/// The member seal: navy on sun yellow.
class _Seal extends StatelessWidget {
  const _Seal();

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    return _TileBox(
      color: palette.marker,
      child: Icon(
        CupertinoIcons.checkmark_seal_fill,
        size: 20,
        color: palette.deep,
      ),
    );
  }
}

/// A sky glyph on navy, on the raised row.
class _GlyphTile extends StatelessWidget {
  const _GlyphTile({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    return _TileBox(
      color: palette.deep,
      child: Icon(icon, size: 20, color: palette.sky),
    );
  }
}

class _TileBox extends StatelessWidget {
  const _TileBox({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    ),
  );
}

/// The raised navy row: a tile, a line or two, and an optional pill beside
/// them, or under them when [stackAction] or the text is large.
class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.tile,
    required this.title,
    this.subtitle,
    this.action,
    this.stackAction = false,
  });

  final Widget tile;
  final String title;
  final String? subtitle;
  final Widget? action;
  final bool stackAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = BisoPalette.of(context);
    final subtitle = this.subtitle;
    final action = this.action;
    final largeText =
        MediaQuery.textScalerOf(context).scale(10) > 10 * _stackPillAbove;
    final stacked = action != null && (stackAction || largeText);

    final lines = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: text.titleSmall?.copyWith(color: _onDeep)),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: text.bodySmall?.copyWith(color: palette.deepMuted),
                ),
            ],
          ),
        ),
        if (stacked) ...[const SizedBox(height: 10), action],
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.deepRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.deepEdge),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          crossAxisAlignment: stacked
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            tile,
            const SizedBox(width: 10),
            Expanded(child: lines),
            if (action != null && !stacked) ...[
              const SizedBox(width: 10),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
