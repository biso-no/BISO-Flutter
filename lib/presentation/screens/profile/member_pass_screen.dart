import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/member_pass.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/member_pass/member_pass_provider.dart';
import '../../../providers/member_pass/member_pass_session.dart';
import '../../../providers/membership/membership_checkout_provider.dart';
import '../../../providers/membership/membership_overview_provider.dart';
import '../../widgets/biso/biso.dart';
import '../../widgets/member_pass/pass_card.dart';
import 'member_pass_presentation.dart';
import 'membership_screen.dart' show membershipLinkUrl;

/// The signed-in member's live pass, or why there is none.
class MemberPassScreen extends ConsumerStatefulWidget {
  const MemberPassScreen({super.key});

  @override
  ConsumerState<MemberPassScreen> createState() => _MemberPassScreenState();
}

class _MemberPassScreenState extends ConsumerState<MemberPassScreen> {
  KeepAliveLink? _hold;

  @override
  void initState() {
    super.initState();
    _hold = ref.read(memberPassProvider.notifier).hold();
  }

  @override
  void dispose() {
    _hold?.close();
    super.dispose();
  }

  Future<void> _openLinkPage() async {
    ref.read(membershipOverviewProvider.notifier).noteLinkStarted();
    final opened = await ref.read(membershipUrlLauncherProvider)(
      membershipLinkUrl,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.memberPassLinkFailed),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final view = ref.watch(memberPassProvider);
    final notifier = ref.read(memberPassProvider.notifier);
    final VoidCallback? retry = view.fetching
        ? null
        : () => unawaited(notifier.retry());

    Widget message({
      required IconData icon,
      required String title,
      String? body,
      required String action,
      required VoidCallback? onPressed,
      BisoAccent accent = BisoAccent.neutral,
    }) {
      return BisoEmptyState(
        icon: icon,
        title: title,
        message: body,
        accent: accent,
        action: FilledButton(onPressed: onPressed, child: Text(action)),
      );
    }

    final Widget body = switch (view.status) {
      PassStatus.loading => const BisoSkeleton.card(),
      PassStatus.active => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PassCard(
            view: view,
            onTap: () => unawaited(showPassPresentation(context)),
          ),
        ],
      ),
      PassStatus.signedOut => message(
        icon: CupertinoIcons.person_crop_circle,
        title: l10n.memberPassSignedOutTitle,
        action: l10n.memberPassSignIn,
        onPressed: () => context.go('/auth/login'),
      ),
      PassStatus.reconnect => message(
        icon: CupertinoIcons.wifi_slash,
        title: l10n.memberPassReconnectTitle,
        body: l10n.memberPassReconnectMessage,
        action: l10n.tryAgainMessage,
        onPressed: retry,
      ),
      PassStatus.noPass => switch (view.noPassState) {
        NoPassState.noBiIdentity => message(
          icon: CupertinoIcons.link,
          title: l10n.memberPassLinkTitle,
          body: l10n.memberPassLinkMessage,
          action: l10n.memberPassLinkAction,
          onPressed: () => unawaited(_openLinkPage()),
          accent: BisoAccent.gold,
        ),
        NoPassState.notMember || NoPassState.expired => message(
          icon: CupertinoIcons.checkmark_seal,
          title: view.noPassState == NoPassState.expired
              ? l10n.memberPassExpiredTitle
              : l10n.memberPassNotMemberTitle,
          body: l10n.memberPassNotMemberMessage,
          action: l10n.memberPassBecomeMember,
          onPressed: () => context.push('/profile/membership'),
          accent: BisoAccent.gold,
        ),
        NoPassState.unavailable || null => message(
          icon: CupertinoIcons.exclamationmark_triangle,
          title: l10n.memberPassUnavailableTitle,
          body: l10n.memberPassUnavailableMessage,
          action: l10n.tryAgainMessage,
          onPressed: retry,
        ),
      },
    };

    return BisoPage(
      title: l10n.memberPassTitle,
      leading: BisoBackButton(
        onPressed: () =>
            NavigationUtils.safeGoBack(context, fallbackRoute: '/profile'),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          sliver: SliverToBoxAdapter(child: body),
        ),
      ],
    );
  }
}
