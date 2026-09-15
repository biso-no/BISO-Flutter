import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'biso_colors.dart';
import 'biso_chrome.dart';

class BisoNavDestination {
  const BisoNavDestination({
    required this.icon,
    required this.label,
    this.activeIcon,
  });
  final IconData icon;
  final IconData? activeIcon;
  final String label;
}

/// Clearance belongs inside scroll content, never around its viewport.
/// Keeping it constant while the bar changes width prevents scroll jumps.
class BisoNavigationInset extends InheritedWidget {
  const BisoNavigationInset({
    super.key,
    required this.bottom,
    required super.child,
  });

  final double bottom;

  static double of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<BisoNavigationInset>()
          ?.bottom ??
      MediaQuery.paddingOf(context).bottom;

  static EdgeInsets padding(BuildContext context, EdgeInsets spacing) =>
      spacing.copyWith(bottom: spacing.bottom + of(context));

  @override
  bool updateShouldNotify(BisoNavigationInset oldWidget) =>
      bottom != oldWidget.bottom;
}

/// A full-height page with glass navigation floating over its scroll content.
class BisoNavigationScaffold extends StatefulWidget {
  const BisoNavigationScaffold({
    super.key,
    required this.child,
    required this.currentIndex,
    required this.destinations,
    required this.onSelected,
    required this.routeKey,
  });
  final Widget child;
  final int currentIndex;
  final List<BisoNavDestination> destinations;
  final ValueChanged<int> onSelected;
  final String routeKey;

  @override
  State<BisoNavigationScaffold> createState() => _BisoNavigationScaffoldState();
}

class _BisoNavigationScaffoldState extends State<BisoNavigationScaffold> {
  bool _collapsed = false;
  double _travel = 0;

  @override
  void didUpdateWidget(BisoNavigationScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeKey != widget.routeKey) {
      _collapsed = false;
      _travel = 0;
    }
  }

  void _expand() {
    if (_collapsed) setState(() => _collapsed = false);
    _travel = 0;
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical ||
        MediaQuery.accessibleNavigationOf(context)) {
      return false;
    }
    final metrics = notification.metrics;
    if (metrics.pixels <= metrics.minScrollExtent + 8) {
      _expand();
    } else if (notification is ScrollUpdateNotification &&
        !metrics.outOfRange) {
      final delta = notification.scrollDelta ?? 0;
      if (delta == 0) return false;
      if (_travel.sign != delta.sign) _travel = 0;
      _travel += delta;
      if (!_collapsed && _travel > 72 && metrics.extentBefore > 100) {
        setState(() => _collapsed = true);
        _travel = 0;
      } else if (_collapsed && _travel < -32) {
        _expand();
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardVisible = media.viewInsets.bottom > 0;
    final clearance = keyboardVisible
        ? 0.0
        : BisoNavigationBar.heightFor(media) +
              media.padding.bottom.clamp(10.0, double.infinity) +
              8;
    return Scaffold(
      // Child Scaffolds already handle the keyboard. Avoid applying it twice.
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          BisoNavigationInset(
            bottom: clearance,
            child: MediaQuery(
              // Nested SafeAreas must not clip the scrolling viewport above
              // the home indicator. Scroll padding owns that clearance too.
              data: media.copyWith(padding: media.padding.copyWith(bottom: 0)),
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: widget.child,
              ),
            ),
          ),
          if (!keyboardVisible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BisoNavigationBar(
                currentIndex: widget.currentIndex,
                destinations: widget.destinations,
                collapsed:
                    _collapsed && !MediaQuery.accessibleNavigationOf(context),
                onExpand: _expand,
                onSelected: (index) {
                  _expand();
                  widget.onSelected(index);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class BisoNavigationBar extends StatelessWidget {
  static double heightFor(MediaQueryData media) =>
      60 + (media.textScaler.scale(12) - 12).clamp(0.0, 24.0);
  const BisoNavigationBar({
    super.key,
    required this.currentIndex,
    required this.destinations,
    required this.onSelected,
    this.collapsed = false,
    this.onExpand,
  });
  final int currentIndex;
  final List<BisoNavDestination> destinations;
  final ValueChanged<int> onSelected;
  final bool collapsed;
  final VoidCallback? onExpand;

  void _select(int index) {
    HapticFeedback.selectionClick();
    onSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    final selectedFill = palette.ink.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.12 : 0.08,
    );
    final active = destinations[currentIndex];
    final duration = media.disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 320);
    final height = heightFor(media);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.clamp(0.0, 420.0);
            return Align(
              alignment: AlignmentDirectional.centerEnd,
              child: AnimatedContainer(
                duration: duration,
                curve: Curves.easeOutCubic,
                width: collapsed ? height : width,
                height: height,
                child: BisoChrome(
                  radius: height / 2,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(height / 2),
                    child: OverflowBox(
                      alignment: AlignmentDirectional.centerEnd,
                      minWidth: 0,
                      maxWidth: width,
                      child: collapsed
                          ? SizedBox(
                              key: const ValueKey('biso-nav-collapsed'),
                              width: height,
                              height: height,
                              child: IconButton(
                                tooltip:
                                    '${active.label}, ${MaterialLocalizations.of(context).showMenuTooltip}',
                                onPressed: onExpand,
                                icon: Icon(
                                  active.activeIcon ?? active.icon,
                                  color: palette.link,
                                  size: 26,
                                ),
                              ),
                            )
                          : SizedBox(
                              key: const ValueKey('biso-nav-expanded'),
                              width: width,
                              height: height,
                              child: Row(
                                children: [
                                  for (var i = 0; i < destinations.length; i++)
                                    Expanded(
                                      child: Semantics(
                                        selected: currentIndex == i,
                                        button: true,
                                        label: destinations[i].label,
                                        excludeSemantics: true,
                                        onTap: () => _select(i),
                                        child: Padding(
                                          padding: const EdgeInsets.all(5),
                                          child: Material(
                                            color: currentIndex == i
                                                ? selectedFill
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              30,
                                            ),
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(30),
                                              onTap: () => _select(i),
                                              child: Center(
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      currentIndex == i
                                                          ? destinations[i]
                                                                    .activeIcon ??
                                                                destinations[i]
                                                                    .icon
                                                          : destinations[i]
                                                                .icon,
                                                      size: 23,
                                                      color: currentIndex == i
                                                          ? palette.link
                                                          : palette.ink,
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      destinations[i].label,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: theme
                                                          .textTheme
                                                          .labelSmall
                                                          ?.copyWith(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: currentIndex == i
                                                                ? palette.link
                                                                : palette.ink,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
