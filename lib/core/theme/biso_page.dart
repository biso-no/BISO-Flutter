import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'biso_colors.dart';
import 'biso_navigation.dart';
import 'biso_page_header.dart';

/// Scroll clearance inside a [BisoPage]. [top] clears the translucent header;
/// [bottom] clears the tab bar and the page's bottom bar.
class BisoPageInsets extends InheritedWidget {
  const BisoPageInsets({
    super.key,
    required this.top,
    required this.bottom,
    required super.child,
  });

  final double top;
  final double bottom;

  static BisoPageInsets? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BisoPageInsets>();

  /// [spacing] plus header and bottom clearance, for `body:` pages whose
  /// scroll views set their own padding.
  static EdgeInsets padding(
    BuildContext context, [
    EdgeInsets spacing = EdgeInsets.zero,
  ]) {
    final insets = maybeOf(context);
    final top =
        insets?.top ?? MediaQuery.paddingOf(context).top + kBisoHeaderHeight;
    final bottom = insets?.bottom ?? BisoNavigationInset.of(context);
    return spacing.copyWith(
      top: spacing.top + top,
      bottom: spacing.bottom + bottom,
    );
  }

  @override
  bool updateShouldNotify(BisoPageInsets oldWidget) =>
      top != oldWidget.top || bottom != oldWidget.bottom;
}

class BisoLargeTitle extends StatelessWidget {
  const BisoLargeTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
    child: Semantics(
      header: true,
      child: Text(
        title,
        key: const ValueKey('biso-large-title'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.headlineLarge?.copyWith(
          color: BisoPalette.of(context).ink,
        ),
      ),
    ),
  );
}

/// Debug builds only. A scroll offset applied to the next BisoPage built, so
/// a scrolled header can be screenshotted on a simulator without gestures.
class BisoPageDebug {
  BisoPageDebug._();

  static final ValueNotifier<double> initialScroll = ValueNotifier(0);
}

/// One scaffold for every BISO screen: a full-screen scroll body with the
/// translucent [BisoPageHeader] floating over it, the way the tab bar floats
/// over the bottom.
class BisoPage extends StatefulWidget {
  const BisoPage({
    super.key,
    this.title,
    this.largeTitle = true,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.actions = const [],
    this.search,
    this.overImage = false,
    this.onRefresh,
    this.slivers,
    this.body,
    this.bottomBar,
    this.controller,
    this.physics,
    this.notificationDepth = 0,
  }) : assert(
         (slivers == null) != (body == null),
         'Provide exactly one of slivers or body.',
       );

  final String? title;

  /// Large Museo title at the start of the content. Detail pages turn it off
  /// and show only the compact title.
  final bool largeTitle;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final List<BisoHeaderAction> actions;
  final BisoHeaderSearch? search;

  /// The content starts with a full-bleed photo under the header.
  final bool overImage;
  final Future<void> Function()? onRefresh;
  final List<Widget>? slivers;
  final Widget? body;

  /// Pinned above the tab bar, e.g. a purchase bar or a message composer.
  final Widget? bottomBar;
  final ScrollController? controller;
  final ScrollPhysics? physics;

  /// Depth of the scroll view that drives the header. Pages whose scroll
  /// views sit inside a PageView use 1.
  final int notificationDepth;

  @override
  State<BisoPage> createState() => _BisoPageState();
}

class _BisoPageState extends State<BisoPage> {
  final _offset = ValueNotifier<double>(0);
  final _largeTitleExtent = ValueNotifier<double>(double.infinity);
  final _bottomBarHeight = ValueNotifier<double>(0);
  Timer? _debugScroll;

  @override
  void initState() {
    super.initState();
    final target = BisoPageDebug.initialScroll.value;
    if (kDebugMode && target > 0 && widget.slivers != null) {
      // Consumed by this page only; later pages must not inherit it.
      BisoPageDebug.initialScroll.value = 0;
      // Content usually arrives asynchronously; wait for it before jumping.
      _debugScroll = Timer(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        final controller =
            widget.controller ?? PrimaryScrollController.maybeOf(context);
        if (controller == null || !controller.hasClients) return;
        if (controller.positions.length != 1) return;
        final position = controller.position;
        controller.jumpTo(target.clamp(0.0, position.maxScrollExtent));
      });
    }
  }

  @override
  void dispose() {
    _debugScroll?.cancel();
    _offset.dispose();
    _largeTitleExtent.dispose();
    _bottomBarHeight.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth == widget.notificationDepth &&
        notification.metrics.axis == Axis.vertical) {
      _offset.value =
          notification.metrics.pixels - notification.metrics.minScrollExtent;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final top = media.padding.top + kBisoHeaderHeight;
    final navigationBottom = media.viewInsets.bottom > 0
        ? 0.0
        : BisoNavigationInset.of(context);
    final showLargeTitle =
        widget.largeTitle && widget.title != null && !widget.overImage;
    final canPop = Navigator.maybeOf(context)?.canPop() ?? false;
    final leading =
        widget.leading ??
        (widget.automaticallyImplyLeading && canPop
            ? const BisoBackButton()
            : null);

    return Scaffold(
      backgroundColor: BisoPalette.of(context).paper,
      body: BackdropGroup(
        child: ValueListenableBuilder<double>(
          valueListenable: _bottomBarHeight,
          builder: (context, barHeight, _) {
            final bottom = navigationBottom + barHeight;
            Widget content =
                widget.body ??
                CustomScrollView(
                  controller: widget.controller,
                  physics:
                      widget.physics ?? const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (!widget.overImage)
                      SliverToBoxAdapter(child: SizedBox(height: top)),
                    if (showLargeTitle)
                      SliverToBoxAdapter(
                        child: _SizeReporter(
                          onSize: (size) =>
                              _largeTitleExtent.value = size.height,
                          child: BisoLargeTitle(widget.title!),
                        ),
                      ),
                    ...widget.slivers!,
                    SliverToBoxAdapter(child: SizedBox(height: bottom + 16)),
                  ],
                );
            if (widget.onRefresh != null) {
              content = RefreshIndicator.adaptive(
                onRefresh: widget.onRefresh!,
                edgeOffset: top,
                notificationPredicate: (n) =>
                    n.depth == widget.notificationDepth,
                child: content,
              );
            }
            return BisoPageInsets(
              top: top,
              bottom: bottom,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScroll,
                      child: content,
                    ),
                  ),
                  if (widget.bottomBar != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: navigationBottom,
                      child: _SizeReporter(
                        onSize: (size) => _bottomBarHeight.value = size.height,
                        child: widget.bottomBar!,
                      ),
                    ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: BisoPageHeader(
                      offset: _offset,
                      largeTitleExtent: _largeTitleExtent,
                      title: widget.title,
                      showLargeTitle: showLargeTitle,
                      leading: leading,
                      actions: widget.actions,
                      search: widget.search,
                      overImage: widget.overImage,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Reports its child's size after layout, so clearance can follow content
/// that changes height (large text, localized titles, bottom bars).
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) {
    renderObject.onSize = onSize;
  }
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _reported) return;
    _reported = size;
    final reported = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(reported));
  }
}
