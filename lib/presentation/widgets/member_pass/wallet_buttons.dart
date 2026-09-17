import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/models/member_pass.dart';
import '../../../data/services/member_pass_api_client.dart';
import '../../../data/services/wallet_channel.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/member_pass/member_pass_provider.dart';
import '../../../providers/membership/membership_checkout_provider.dart';
import '../biso/biso.dart';

/// Apple's badge with its styles inlined for flutter_svg; the originals in
/// assets/wallet/apple are the sources (see tool/inline_svg_styles.py).
const appleWalletBadge = {
  'en': 'assets/wallet/apple/flutter/add_to_wallet_en.svg',
  'no': 'assets/wallet/apple/flutter/add_to_wallet_no.svg',
};

const googleWalletBadge = {
  'en': 'assets/wallet/google/add_to_wallet_en.svg',
  'no': 'assets/wallet/google/add_to_wallet_no.svg',
};

/// Each badge's own width and height (its SVG root `width`/`height`), so its
/// aspect ratio can be kept once it is drawn at a fixed height. flutter_svg
/// never infers a missing dimension from the picture itself — leaving the
/// width unset renders it zero-wide.
const _badgeNaturalSize = <String, Size>{
  'assets/wallet/apple/flutter/add_to_wallet_en.svg': Size(110.739, 35.016),
  'assets/wallet/apple/flutter/add_to_wallet_no.svg': Size(136.284, 35.026),
  'assets/wallet/google/add_to_wallet_en.svg': Size(199, 55),
  'assets/wallet/google/add_to_wallet_no.svg': Size(199, 55),
};

/// The platform's own Add to Wallet badge, when the server offers that
/// wallet: Apple's on iOS, Google's on Android, never both.
class WalletButtons extends ConsumerStatefulWidget {
  const WalletButtons({super.key, required this.wallets});

  final WalletAvailability wallets;

  @override
  ConsumerState<WalletButtons> createState() => _WalletButtonsState();
}

class _WalletButtonsState extends ConsumerState<WalletButtons> {
  bool _busy = false;
  bool _added = false;

  String _badge(Map<String, String> assets) {
    final language = Localizations.localeOf(context).languageCode;
    return assets[language] ?? assets['en']!;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS when widget.wallets.apple:
        final canAdd =
            ref.watch(canAddApplePassesProvider).valueOrNull ?? false;
        if (!canAdd) return const SizedBox.shrink();
        if (_added) return _AddedLabel(text: l10n.walletAdded);
        return _Badge(
          asset: _badge(appleWalletBadge),
          label: l10n.walletAddAppleLabel,
          busy: _busy,
          onPressed: _addApple,
        );
      case TargetPlatform.android when widget.wallets.google:
        return _Badge(
          asset: _badge(googleWalletBadge),
          label: l10n.walletAddGoogleLabel,
          busy: _busy,
          onPressed: _addGoogle,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _addApple() => _run(() async {
    final bytes = await ref.read(memberPassApiProvider).fetchApplePass();
    final result = await ref.read(walletChannelProvider).addPass(bytes);
    if (result == WalletAddResult.added && mounted) {
      setState(() => _added = true);
    }
  });

  Future<void> _addGoogle() => _run(() async {
    final url = await ref.read(memberPassApiProvider).fetchGoogleSaveUrl();
    final opened = await ref.read(membershipUrlLauncherProvider)(url);
    if (!opened) _say((l10n) => l10n.walletErrorFailed);
  });

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on MemberPassApiException catch (error) {
      if (error.isUnauthorized) {
        // The pass screen re-checks and shows the sign-in prompt.
        unawaited(ref.read(memberPassProvider.notifier).retry());
      } else if (error.isForbidden) {
        _say((l10n) => l10n.walletErrorNotMember);
      } else if (error.isNotFound) {
        _say((l10n) => l10n.walletErrorNotConfigured);
      } else {
        _say((l10n) => l10n.walletErrorFailed);
      }
    } on PlatformException catch (error) {
      _say(
        (l10n) => error.code == 'invalid_pass'
            ? l10n.walletErrorInvalid
            : l10n.walletErrorFailed,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String Function(AppLocalizations l10n) text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text(AppLocalizations.of(context)!))),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.asset,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String asset;
  final String label;
  final bool busy;
  final VoidCallback onPressed;

  static const _height = 48.0;

  @override
  Widget build(BuildContext context) {
    final natural = _badgeNaturalSize[asset];
    final width = natural == null
        ? null
        : _height * natural.width / natural.height;
    return Center(
      child: Semantics(
        button: true,
        enabled: !busy,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          // The SVG badge paints through a picture layer that never claims
          // its own hits (flutter_svg draws it, it does not make it
          // interactive), so the tap area must claim the whole box itself
          // rather than defer to that child.
          behavior: HitTestBehavior.opaque,
          onTap: busy ? null : onPressed,
          child: AnimatedOpacity(
            opacity: busy ? 0.5 : 1,
            duration: const Duration(milliseconds: 150),
            child: SvgPicture.asset(asset, width: width, height: _height),
          ),
        ),
      ),
    );
  }
}

class _AddedLabel extends StatelessWidget {
  const _AddedLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(CupertinoIcons.checkmark_circle_fill, color: palette.muted),
        const SizedBox(width: 6),
        Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: palette.muted),
        ),
      ],
    );
  }
}
