import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/biso_colors.dart';
import '../../data/models/update_decision.dart';
import '../../data/services/store_updater.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/config/update_prompt_provider.dart';

/// Covers the whole app with an "update to keep using the app" screen while
/// [updatePromptProvider] is [UpdatePrompt.required].
///
/// Sits in `MaterialApp.router`'s `builder`, above the Navigator, so nothing
/// the app routes to can appear on top of it. [child] stays mounted
/// underneath — its providers, routes and state carry on — but while the
/// block is up nothing in it can be touched, focused or read by a screen
/// reader, and system back reaches neither the block nor the routes hidden
/// under it. There is no way past the block except updating; it lifts only
/// when a fresh answer says this version is fine.
///
/// Being above the Navigator, there is no `Navigator` or `Overlay` here:
/// nothing in the block may need one (no dialogs or tooltips), and a
/// `PopScope` would have no route to guard.
class UpdateRequiredOverlay extends ConsumerWidget {
  const UpdateRequiredOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(updatePromptProvider) == UpdatePrompt.required;
    return _SystemBackGuard(
      blocked: blocked,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The same widgets either way, so the app keeps its state when the
          // block comes and goes.
          ExcludeFocus(
            excluding: blocked,
            child: AbsorbPointer(absorbing: blocked, child: child),
          ),
          if (blocked) const BlockSemantics(child: _UpdateRequiredScreen()),
        ],
      ),
    );
  }
}

/// Keeps system back away from the app while [blocked].
///
/// A back button press reaches the app as a `popRoute`, offered to every
/// [WidgetsBindingObserver] in the order they were added until one handles
/// it. The router's back button dispatcher is one of them, added when the
/// router below first builds; this guard is added before it, when the
/// overlay first builds, and handles every back press while [blocked]. It is
/// added for the overlay's whole life because one added later, when a block
/// arrives, would be asked only after the router had already popped a
/// route.
///
/// Android's predictive back gesture skips `popRoute`: it goes straight to
/// the top route, which pops itself. The platform only sends it while the app
/// says it can handle back, which the app's navigators report through
/// [NavigationNotification]s on their way up to `WidgetsApp`. While
/// [blocked] they stop here, and the guard reports that the app cannot handle
/// back, so the system takes the gesture and leaves the app instead. Once the
/// block lifts, the navigators' last report is passed on again.
class _SystemBackGuard extends StatefulWidget {
  const _SystemBackGuard({required this.blocked, required this.child});

  final bool blocked;
  final Widget child;

  @override
  State<_SystemBackGuard> createState() => _SystemBackGuardState();
}

class _SystemBackGuardState extends State<_SystemBackGuard>
    with WidgetsBindingObserver {
  /// Whether the app's navigators last said they could handle back.
  bool _appCanHandlePop = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.blocked) _reportCanHandlePop();
  }

  @override
  void didUpdateWidget(_SystemBackGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blocked != widget.blocked) _reportCanHandlePop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async => widget.blocked;

  bool _onNavigation(NavigationNotification notification) {
    _appCanHandlePop = notification.canHandlePop;
    return widget.blocked;
  }

  void _reportCanHandlePop() {
    // After the frame, as the Navigator does: never in the middle of a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      NavigationNotification(
        canHandlePop: !widget.blocked && _appCanHandlePop,
      ).dispatch(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<NavigationNotification>(
      onNotification: _onNavigation,
      child: widget.child,
    );
  }
}

class _UpdateRequiredScreen extends StatelessWidget {
  const _UpdateRequiredScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    final l10n = AppLocalizations.of(context)!;
    final dark = theme.brightness == Brightness.dark;

    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: Material(
        color: palette.paper,
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),
                      Image.asset(
                        dark ? 'assets/logo-dark.png' : 'assets/logo.png',
                        height: 72,
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
                      ),
                      const SizedBox(height: 32),
                      Semantics(
                        header: true,
                        namesRoute: true,
                        child: Text(
                          l10n.updateRequiredTitle,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: palette.ink,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.updateRequiredBody,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: palette.muted,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const Spacer(),
                      const SizedBox(height: 32),
                      const _UpdateButton(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Starts the store update, and stays disabled until the store is done with
/// it: two updates started at once would open the store twice.
class _UpdateButton extends ConsumerStatefulWidget {
  const _UpdateButton();

  @override
  ConsumerState<_UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends ConsumerState<_UpdateButton> {
  bool _updating = false;

  Future<void> _update() async {
    setState(() => _updating = true);
    try {
      await ref.read(storeUpdaterProvider).startUpdate();
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: _updating ? null : _update,
      child: Text(AppLocalizations.of(context)!.updateButton),
    );
  }
}
