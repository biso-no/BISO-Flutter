import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/oslo_time.dart';
import '../../../data/models/campus_benefit.dart';
import '../../../data/services/benefits_api_client.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/benefits/benefit_standing.dart';
import '../../../providers/benefits/benefits_providers.dart';
import '../../../providers/member_pass/member_pass_provider.dart';
import '../../screens/auth/continue_with_bi_action.dart';
import '../../screens/profile/member_pass_presentation.dart';
import '../biso/biso.dart';

/// Text on the navy panels, which stay navy in both themes.
const _onDeep = Colors.white;

/// [value] as an https link with a host, or null. Codes, links and partner
/// websites open only this way.
Uri? benefitHttpsUri(String? value) {
  final uri = Uri.tryParse(value?.trim() ?? '');
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  return uri;
}

enum _Reveal {
  idle,
  loading,
  revealed,
  membersOnly,
  unavailable,
  notFound,
  linkFailed,
}

/// How a deal is claimed, for the standing the student has.
///
/// The code or link a member reveals lives in this widget's state only:
/// never in a provider, a log or analytics, and it goes when the page closes.
class BenefitActionPanel extends ConsumerStatefulWidget {
  const BenefitActionPanel({
    super.key,
    required this.benefit,
    required this.otherCount,
    required this.campusName,
  });

  final CampusBenefit benefit;

  /// The campus's other benefits, for the locked text. 0 leaves the count
  /// out.
  final int otherCount;
  final String campusName;

  @override
  ConsumerState<BenefitActionPanel> createState() => _BenefitActionPanelState();
}

class _BenefitActionPanelState extends ConsumerState<BenefitActionPanel> {
  _Reveal _reveal = _Reveal.idle;

  /// The revealed code. Only ever held here, and cleared in [dispose].
  String? _code;

  /// A BI sync or sign-in is running.
  bool _biBusy = false;

  @override
  void dispose() {
    _code = null;
    super.dispose();
  }

  Future<void> _doReveal() async {
    // One reveal at a time, however fast the taps come.
    if (_reveal == _Reveal.loading) return;
    final type = widget.benefit.redemptionType;
    setState(() => _reveal = _Reveal.loading);
    try {
      final value = await ref
          .read(benefitsApiProvider)
          .reveal(widget.benefit.id);
      if (!mounted) return;
      if (type == BenefitRedemptionType.link) {
        await _openLink(value);
        return;
      }
      setState(() {
        _code = value;
        _reveal = _Reveal.revealed;
      });
    } on BenefitsApiException catch (e) {
      if (!mounted) return;
      setState(() => _reveal = _revealFailure(e.kind));
    } on Object {
      if (!mounted) return;
      setState(() => _reveal = _Reveal.unavailable);
    }
  }

  _Reveal _revealFailure(BenefitsApiErrorKind kind) => switch (kind) {
    BenefitsApiErrorKind.notMember => _Reveal.membersOnly,
    BenefitsApiErrorKind.notFound ||
    BenefitsApiErrorKind.noCode => _Reveal.notFound,
    _ => _Reveal.unavailable,
  };

  Future<void> _openLink(String value) async {
    final uri = benefitHttpsUri(value);
    if (uri == null) {
      setState(() => _reveal = _Reveal.notFound);
      return;
    }
    var opened = false;
    try {
      opened = await ref.read(benefitLinkOpenerProvider)(uri);
    } on Object {
      opened = false;
    }
    if (!mounted) return;
    setState(() => _reveal = opened ? _Reveal.idle : _Reveal.linkFailed);
  }

  Future<void> _copy(AppLocalizations l10n) async {
    final code = _code;
    if (code == null) return;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: code));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.benefitsCopied)));
  }

  /// "Til butikken": the partner's website. A failure says so and leaves
  /// the code on screen.
  Future<void> _openWebsite(Uri uri, AppLocalizations l10n) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await ref.read(benefitLinkOpenerProvider)(uri);
    } on Object {
      opened = false;
    }
    if (opened || !mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.benefitsLinkFailed)));
  }

  void _retryOutage(BenefitStanding standing) {
    if (standing == BenefitStanding.unavailable) {
      unawaited(ref.read(memberPassProvider.notifier).retry());
    }
    if (_reveal == _Reveal.unavailable) unawaited(_doReveal());
  }

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
    final info = ref.watch(benefitStandingProvider);
    return _panel(l10n, info) ?? const SizedBox.shrink();
  }

  Widget? _panel(AppLocalizations l10n, BenefitStandingInfo info) {
    final standing = info.standing;
    final type = widget.benefit.redemptionType;

    // Already delivered: keep it visible through a passing outage.
    final canKeepCode =
        standing == BenefitStanding.member ||
        standing == BenefitStanding.unavailable ||
        standing == BenefitStanding.checking;
    final code = _code;
    if (_reveal == _Reveal.revealed && code != null && canKeepCode) {
      return _CodePanel(
        code: code,
        website: benefitHttpsUri(widget.benefit.partner?.websiteUrl),
        onCopy: () => unawaited(_copy(l10n)),
        onWebsite: (uri) => unawaited(_openWebsite(uri, l10n)),
      );
    }

    switch (standing) {
      case BenefitStanding.signedOut:
        return _LockedPanel(
          body: l10n.benefitsLockedSignedOutBody,
          action: l10n.benefitsSignInAction,
          onPressed: () => context.go('/auth/login'),
        );
      case BenefitStanding.upcoming:
        final start = info.upcomingStart;
        if (start == null) return null;
        return _Card(
          children: [
            _Header(
              tile: const BisoIconTile(icon: CupertinoIcons.calendar, size: 40),
              body: l10n.benefitsUpcomingPanel(
                formatOsloDate(start, l10n.localeName),
              ),
            ),
          ],
        );
      case BenefitStanding.needsBi:
        return _Card(
          children: [
            _Header(
              tile: const BisoIconTile(
                icon: CupertinoIcons.person_crop_rectangle,
                accent: BisoAccent.gold,
                size: 40,
              ),
              title: l10n.membershipNeedsBiLinkTitle,
              body: l10n.membershipNeedsBiLinkBody,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _biBusy ? null : () => unawaited(_continueWithBi()),
              child: Text(l10n.membershipNeedsBiLinkCta),
            ),
          ],
        );
      case BenefitStanding.notMember:
        return _membersOnly(l10n);
      case BenefitStanding.member ||
          BenefitStanding.checking ||
          BenefitStanding.unavailable:
        break;
    }
    if (_reveal == _Reveal.membersOnly) return _membersOnly(l10n);

    if (type == BenefitRedemptionType.none) {
      if (standing != BenefitStanding.member) return null;
      return _Card(
        children: [
          _Header(
            tile: const _Tile(
              icon: CupertinoIcons.checkmark_seal_fill,
              seal: true,
            ),
            body: l10n.benefitsMemberHasIt,
          ),
        ],
      );
    }

    final actionLabel = switch (type) {
      BenefitRedemptionType.onsite => l10n.benefitsShowMemberCard,
      BenefitRedemptionType.link => l10n.benefitsOpenDeal,
      _ => l10n.benefitsRevealCode,
    };

    // Neutral: no copy that reads as either answer, only a waiting pill.
    if (standing == BenefitStanding.checking) {
      return _Pill(label: actionLabel, onPressed: null, busy: true);
    }
    if (standing == BenefitStanding.unavailable ||
        _reveal == _Reveal.unavailable) {
      return _MessageCard(
        icon: CupertinoIcons.exclamationmark_circle,
        message: l10n.benefitsUnavailable,
        action: l10n.retry,
        onPressed: () => _retryOutage(standing),
      );
    }
    if (_reveal == _Reveal.notFound) {
      return _MessageCard(
        icon: CupertinoIcons.info_circle,
        message: l10n.benefitsNotFound,
      );
    }
    if (_reveal == _Reveal.linkFailed) {
      return _MessageCard(
        icon: CupertinoIcons.link,
        message: l10n.benefitsLinkFailed,
        action: l10n.retry,
        onPressed: () => unawaited(_doReveal()),
      );
    }

    if (type == BenefitRedemptionType.onsite) {
      return _TillCard(
        onPressed: () => unawaited(showPassPresentation(context)),
      );
    }

    final loading = _reveal == _Reveal.loading;
    return _Pill(
      label: actionLabel,
      busy: loading,
      onPressed: loading ? null : () => unawaited(_doReveal()),
    );
  }

  Widget _membersOnly(AppLocalizations l10n) => _LockedPanel(
    body: l10n.benefitsLockedBody(widget.otherCount, widget.campusName),
    action: l10n.benefitsBecomeMember,
    onPressed: () => unawaited(context.push('/profile/membership')),
  );
}

/// A full-width pill in the theme's primary colour, or a spinner while
/// [busy]. The spinner still reads as [label] to a screen reader.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: onPressed,
      child: busy
          ? Semantics(
              label: label,
              excludeSemantics: true,
              child: const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Text(label, textAlign: TextAlign.center),
    ),
  );
}

/// The light card the member and neutral states sit in.
class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: BisoPalette.of(context).surface,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

/// The navy panel, navy in both themes with a hairline edge.
class _DeepPanel extends StatelessWidget {
  const _DeepPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.deep,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.deepEdge),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// A rounded glyph tile: sky on navy, or navy on the sun-yellow seal.
class _Tile extends StatelessWidget {
  const _Tile({required this.icon, this.seal = false, this.raised = false});

  final IconData icon;

  /// The member seal: navy on sun yellow.
  final bool seal;

  /// On a navy panel, so a step lighter than it.
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final fill = seal
        ? palette.marker
        : raised
        ? palette.deepRaised
        : palette.deep;
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(10),
        ),
        child: SizedBox.square(
          dimension: 40,
          child: Icon(icon, size: 24, color: seal ? palette.deep : palette.sky),
        ),
      ),
    );
  }
}

/// A tile beside a title and a line of text.
class _Header extends StatelessWidget {
  const _Header({
    required this.tile,
    this.title,
    required this.body,
    this.onDeep = false,
  });

  final Widget tile;
  final String? title;
  final String body;
  final bool onDeep;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = BisoPalette.of(context);
    final title = this.title;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tile,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Text(
                  title,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: onDeep ? _onDeep : palette.ink,
                  ),
                ),
                const SizedBox(height: 2),
              ],
              Text(
                body,
                style: text.bodyMedium?.copyWith(
                  color: onDeep
                      ? palette.deepMuted
                      : title == null
                      ? palette.ink
                      : palette.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A member's onsite deal: show the card at the till.
class _TillCard extends StatelessWidget {
  const _TillCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _Card(
      children: [
        _Header(
          tile: const _Tile(icon: CupertinoIcons.creditcard),
          title: l10n.benefitsUseAtTillTitle,
          body: l10n.benefitsUseAtTillBody,
        ),
        const SizedBox(height: 16),
        _Pill(label: l10n.benefitsShowMemberCard, onPressed: onPressed),
      ],
    );
  }
}

/// A line of text with an optional retry, for outages and gone deals.
class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.message,
    this.action,
    this.onPressed,
  });

  final IconData icon;
  final String message;
  final String? action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    return _Card(
      children: [
        _Header(
          tile: BisoIconTile(icon: icon, size: 40),
          body: message,
        ),
        if (action != null) ...[
          const SizedBox(height: 16),
          _Pill(label: action, onPressed: onPressed),
        ],
      ],
    );
  }
}

/// "Bare for BISO-medlemmer", with a sky pill to join or sign in.
class _LockedPanel extends StatelessWidget {
  const _LockedPanel({
    required this.body,
    required this.action,
    required this.onPressed,
  });

  final String body;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _DeepPanel(
      children: [
        _Header(
          tile: const _Tile(icon: CupertinoIcons.lock_fill, raised: true),
          title: l10n.benefitsLockedTitle,
          body: body,
          onDeep: true,
        ),
        const SizedBox(height: 16),
        FilledButton(
          style: _skyPill(BisoPalette.of(context)),
          onPressed: onPressed,
          child: Text(action, textAlign: TextAlign.center),
        ),
      ],
    );
  }
}

ButtonStyle _skyPill(BisoPalette palette) => FilledButton.styleFrom(
  backgroundColor: palette.sky,
  foregroundColor: palette.deep,
);

/// The revealed code, large, with copy and the partner's shop.
class _CodePanel extends StatelessWidget {
  const _CodePanel({
    required this.code,
    required this.website,
    required this.onCopy,
    required this.onWebsite,
  });

  final String code;
  final Uri? website;
  final VoidCallback onCopy;
  final ValueChanged<Uri> onWebsite;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final palette = BisoPalette.of(context);
    final website = this.website;
    return _DeepPanel(
      children: [
        Text(
          l10n.benefitsYourCode,
          style: text.titleSmall?.copyWith(color: palette.deepMuted),
        ),
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.deepRaised,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            child: Text(
              code,
              textAlign: TextAlign.center,
              style: text.headlineSmall?.copyWith(
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Menlo', 'Courier'],
                letterSpacing: 2,
                color: _onDeep,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: _skyPill(palette),
                onPressed: onCopy,
                icon: const Icon(CupertinoIcons.doc_on_doc, size: 18),
                label: Text(l10n.benefitsCopy),
              ),
            ),
            if (website != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _onDeep.withValues(alpha: 0.12),
                    foregroundColor: _onDeep,
                  ),
                  onPressed: () => onWebsite(website),
                  icon: const Icon(CupertinoIcons.arrow_up_right, size: 18),
                  label: Text(l10n.benefitsToShop),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Text(
          l10n.benefitsCodeNote,
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(color: palette.deepMuted),
        ),
      ],
    );
  }
}
