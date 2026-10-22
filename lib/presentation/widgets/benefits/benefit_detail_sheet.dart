import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/oslo_time.dart';
import '../../../data/models/campus_benefit.dart';
import '../../../data/models/member_pass.dart';
import '../../../data/services/benefits_api_client.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/benefits/benefits_providers.dart';
import '../../../providers/member_pass/member_pass_provider.dart';
import '../../../providers/member_pass/member_pass_session.dart';
import '../../screens/profile/member_pass_presentation.dart';
import '../biso/biso.dart';

/// Opens a link outside the app. A provider so tests can see what opens.
final benefitLinkOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Opens [benefit] in a sheet. The code or link a member reveals there
/// lives in the sheet's own state and goes when the sheet closes.
Future<void> showBenefitDetailSheet(
  BuildContext context, {
  required CampusBenefit benefit,
}) => showBisoSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => BenefitDetailSheet(benefit: benefit),
);

/// What the sheet can say about the member's standing, from the pass view.
enum _Standing { active, notMember, signedOut, checking, outage }

_Standing _standingOf(MemberPassView view) => switch (view.status) {
  PassStatus.active => _Standing.active,
  PassStatus.signedOut => _Standing.signedOut,
  PassStatus.noPass => switch (view.noPassState) {
    NoPassState.noBiIdentity ||
    NoPassState.notMember ||
    NoPassState.expired => _Standing.notMember,
    // The pass could not be checked: an outage, never "not a member".
    NoPassState.unavailable || null => _Standing.outage,
  },
  // Still checking: no copy yet. Offline: we do not know, so we never say
  // "not a member".
  PassStatus.loading => _Standing.checking,
  PassStatus.reconnect => _Standing.outage,
};

enum _Reveal {
  idle,
  loading,
  revealed,
  membersOnly,
  unavailable,
  notFound,
  linkFailed,
}

class BenefitDetailSheet extends ConsumerStatefulWidget {
  const BenefitDetailSheet({super.key, required this.benefit});

  final CampusBenefit benefit;

  @override
  ConsumerState<BenefitDetailSheet> createState() => _BenefitDetailSheetState();
}

class _BenefitDetailSheetState extends ConsumerState<BenefitDetailSheet> {
  _Reveal _reveal = _Reveal.idle;

  /// The revealed code. Only ever held here; never passed to a provider,
  /// a log or analytics, and cleared in [dispose].
  String? _code;

  @override
  void dispose() {
    _code = null;
    super.dispose();
  }

  Future<void> _doReveal() async {
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
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
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

  void _becomeMember() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    unawaited(router.push('/profile/membership'));
  }

  void _retryOutage(_Standing standing) {
    if (standing == _Standing.outage) {
      unawaited(ref.read(memberPassProvider.notifier).retry());
    }
    if (_reveal == _Reveal.unavailable) unawaited(_doReveal());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final palette = BisoPalette.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final benefit = widget.benefit;
    final standing = ref.watch(memberPassProvider.select(_standingOf));
    final description = benefit.description.resolve(language);
    final terms = benefit.terms.resolve(language);
    final end = benefit.publishEnd;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (benefit.partner != null)
              Text(
                benefit.partner!.name,
                style: text.bodyMedium?.copyWith(color: palette.muted),
              ),
            Text(benefit.title.resolve(language) ?? '', style: text.titleLarge),
            if (description != null) ...[
              const SizedBox(height: 12),
              Text(description, style: text.bodyLarge),
            ],
            if (end != null) ...[
              const SizedBox(height: 12),
              Text(
                l10n.benefitsValidUntil(formatOsloDate(end, l10n.localeName)),
                style: text.bodyMedium?.copyWith(color: palette.muted),
              ),
            ],
            if (terms != null)
              _TermsDisclosure(title: l10n.benefitsTerms, terms: terms),
            const SizedBox(height: 16),
            ..._action(context, l10n, standing),
          ],
        ),
      ),
    );
  }

  List<Widget> _action(
    BuildContext context,
    AppLocalizations l10n,
    _Standing standing,
  ) {
    final type = widget.benefit.redemptionType;
    if (type == BenefitRedemptionType.none) return const [];

    // Already delivered: keep it visible through a passing outage.
    final canKeepCode =
        standing == _Standing.active ||
        standing == _Standing.outage ||
        standing == _Standing.checking;
    if (_reveal == _Reveal.revealed && _code != null && canKeepCode) {
      return _codeView(context, l10n, _code!);
    }
    if (standing == _Standing.signedOut) {
      return [_line(context, l10n.benefitsSignIn)];
    }
    if (standing == _Standing.notMember || _reveal == _Reveal.membersOnly) {
      return _membersOnly(l10n);
    }
    if (standing == _Standing.checking) {
      return [
        const FilledButton(
          onPressed: null,
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ];
    }
    if (standing == _Standing.outage || _reveal == _Reveal.unavailable) {
      return _message(
        l10n.benefitsUnavailable,
        retry: () => _retryOutage(standing),
        l10n: l10n,
      );
    }
    if (_reveal == _Reveal.notFound) {
      return [_line(context, l10n.benefitsNotFound)];
    }
    if (_reveal == _Reveal.linkFailed) {
      return _message(
        l10n.benefitsLinkFailed,
        retry: () => unawaited(_doReveal()),
        l10n: l10n,
      );
    }

    if (type == BenefitRedemptionType.onsite) {
      return [
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(showPassPresentation(context));
          },
          child: Text(l10n.benefitsShowCard),
        ),
      ];
    }

    final loading = _reveal == _Reveal.loading;
    return [
      FilledButton(
        onPressed: loading ? null : () => unawaited(_doReveal()),
        child: loading
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                type == BenefitRedemptionType.link
                    ? l10n.benefitsOpenLink
                    : l10n.benefitsShowCode,
              ),
      ),
    ];
  }

  Widget _line(BuildContext context, String message) => Text(
    message,
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.bodyLarge,
  );

  List<Widget> _membersOnly(AppLocalizations l10n) => [
    _line(context, l10n.benefitsMembersOnly),
    const SizedBox(height: 12),
    FilledButton(
      onPressed: _becomeMember,
      child: Text(l10n.benefitsBecomeMember),
    ),
  ];

  List<Widget> _message(
    String message, {
    required VoidCallback retry,
    required AppLocalizations l10n,
  }) => [
    _line(context, message),
    const SizedBox(height: 12),
    FilledButton(onPressed: retry, child: Text(l10n.retry)),
  ];

  List<Widget> _codeView(
    BuildContext context,
    AppLocalizations l10n,
    String code,
  ) {
    final palette = BisoPalette.of(context);
    return [
      DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Text(
            code,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: () => unawaited(_copy(l10n)),
        icon: const Icon(CupertinoIcons.doc_on_doc, size: 18),
        label: Text(l10n.benefitsCopy),
      ),
    ];
  }
}

/// "Vilkår": a tappable row that folds the terms open and closed.
class _TermsDisclosure extends StatefulWidget {
  const _TermsDisclosure({required this.title, required this.terms});

  final String title;
  final String terms;

  @override
  State<_TermsDisclosure> createState() => _TermsDisclosureState();
}

class _TermsDisclosureState extends State<_TermsDisclosure> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = BisoPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(child: Text(widget.title, style: text.titleSmall)),
                Icon(
                  _open
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 16,
                  color: palette.muted,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topLeft,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(widget.terms, style: text.bodyMedium),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
