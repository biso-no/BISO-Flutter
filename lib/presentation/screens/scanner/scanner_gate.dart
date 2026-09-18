import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/navigation_utils.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/member_pass/scanner_access_provider.dart';
import '../../widgets/biso/biso.dart';
import 'membership_scanner_screen.dart';

/// Shows the scanner only to users the server calls scanners. The camera
/// is not created until then.
class ScannerGate extends ConsumerStatefulWidget {
  const ScannerGate({super.key});

  @override
  ConsumerState<ScannerGate> createState() => _ScannerGateState();
}

class _ScannerGateState extends ConsumerState<ScannerGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref.read(scannerAccessProvider.notifier).ensureFresh(force: true),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(scannerAccessProvider);
    final value = async.valueOrNull;
    if (value is ScannerGranted) {
      return MembershipScannerScreen(access: value.access);
    }

    final Widget body;
    if (value == null || async.isLoading) {
      body = const CupertinoActivityIndicator();
    } else {
      body = switch (value) {
        ScannerDenied() => BisoEmptyState(
          icon: CupertinoIcons.lock,
          title: l10n.scannerNoAccess,
        ),
        ScannerSignedOut() => BisoEmptyState(
          icon: CupertinoIcons.person_crop_circle,
          title: l10n.scannerSignedOut,
          action: FilledButton(
            onPressed: () => context.go('/auth/login'),
            child: Text(l10n.memberPassSignIn),
          ),
        ),
        ScannerNotConfigured() => BisoEmptyState(
          icon: CupertinoIcons.exclamationmark_triangle,
          title: l10n.scannerNotConfigured,
        ),
        ScannerCheckFailed() => BisoEmptyState(
          icon: CupertinoIcons.wifi_slash,
          title: l10n.scannerCheckFailed,
          action: FilledButton(
            onPressed: () => unawaited(
              ref.read(scannerAccessProvider.notifier).ensureFresh(force: true),
            ),
            child: Text(l10n.tryAgainMessage),
          ),
        ),
        ScannerGranted() => const SizedBox.shrink(),
      };
    }

    return BisoPage(
      title: l10n.scannerTitle,
      largeTitle: false,
      leading: BisoBackButton(
        onPressed: () =>
            NavigationUtils.safeGoBack(context, fallbackRoute: '/explore'),
      ),
      body: Center(child: body),
    );
  }
}
