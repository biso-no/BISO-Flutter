import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/screen_presentation.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/member_pass/member_pass_provider.dart';
import '../../../providers/member_pass/member_pass_session.dart';
import '../../widgets/member_pass/pass_card.dart';
import '../../widgets/member_pass/pass_colors.dart';

/// Shows the pass full screen, above the tab bar.
Future<void> showPassPresentation(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      fullscreenDialog: true,
      pageBuilder: (_, _, _) => const MemberPassPresentation(),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// The pass, large, with the screen kept awake and at full brightness.
/// Both are undone whenever the app leaves the foreground and when this
/// closes, so a forgotten presentation never leaves the phone bright.
class MemberPassPresentation extends ConsumerStatefulWidget {
  const MemberPassPresentation({super.key});

  @override
  ConsumerState<MemberPassPresentation> createState() =>
      _MemberPassPresentationState();
}

class _MemberPassPresentationState extends ConsumerState<MemberPassPresentation>
    with WidgetsBindingObserver {
  KeepAliveLink? _hold;
  late final ScreenPresentation _screen;
  bool _applied = false;

  @override
  void initState() {
    super.initState();
    _hold = ref.read(memberPassProvider.notifier).hold();
    _screen = ref.read(screenPresentationProvider);
    WidgetsBinding.instance.addObserver(this);
    _apply();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _apply();
    } else {
      _restore();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restore();
    _hold?.close();
    super.dispose();
  }

  void _apply() {
    if (_applied) return;
    _applied = true;
    unawaited(_screen.enter());
  }

  void _restore() {
    if (!_applied) return;
    _applied = false;
    unawaited(_screen.exit());
  }

  void _close() => unawaited(Navigator.of(context).maybePop());

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(memberPassProvider);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: PassColors.card,
      body: SafeArea(
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              onVerticalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) > 300) _close();
              },
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: view.status == PassStatus.active
                      ? PassCard(view: view, presentation: true)
                      : Text(
                          l10n.memberPassUnavailableTitle,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: PassColors.cardInk),
                        ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: _close,
                icon: const Icon(
                  CupertinoIcons.xmark,
                  color: PassColors.cardInk,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
