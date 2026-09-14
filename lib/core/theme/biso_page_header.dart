import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'biso_chrome.dart';
import 'biso_colors.dart';

/// Height of the header row below the status bar.
const double kBisoHeaderHeight = 52;

/// Scroll distance over which the header band fades in.
const double _fadeDistance = 12;

class BisoHeaderAction {
  const BisoHeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badge,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// A count shown on the button, such as the items in the cart.
  final int? badge;
}

class BisoHeaderSearch {
  const BisoHeaderSearch({
    required this.hintText,
    required this.onChanged,
    this.initialQuery = '',
    this.debounce = const Duration(milliseconds: 350),
    this.onExpansionChanged,
  });

  final String hintText;
  final ValueChanged<String> onChanged;
  final String initialQuery;
  final Duration debounce;
  final ValueChanged<bool>? onExpansionChanged;
}

/// Floating native glass holding one or more [BisoCapsuleButton]s.
class BisoGlassCapsule extends StatelessWidget {
  const BisoGlassCapsule({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => BisoChrome(
    radius: 24,
    child: SizedBox(
      height: 48,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}

class BisoCapsuleButton extends StatelessWidget {
  const BisoCapsuleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.badge,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Defaults to the ambient icon color, which the header sets.
  final Color? color;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final count = badge ?? 0;
    return SizedBox.square(
      dimension: 48,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          backgroundColor: palette.link,
          textColor: palette.onPrimary,
          child: Icon(
            icon,
            size: 22,
            color: color ?? IconTheme.of(context).color ?? palette.ink,
          ),
        ),
      ),
    );
  }
}

class BisoBackButton extends StatelessWidget {
  const BisoBackButton({super.key, this.onPressed});

  /// Defaults to [Navigator.maybePop]. Routes reached with `context.go` pass
  /// `NavigationUtils.safeGoBack` so there is always somewhere to go.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => BisoGlassCapsule(
    children: [
      BisoCapsuleButton(
        icon: CupertinoIcons.chevron_back,
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: onPressed ?? () => Navigator.maybePop(context),
      ),
    ],
  );
}

/// The translucent header of a BisoPage.
///
/// At rest it draws no bar: only the floating back button and action capsule.
/// As [offset] grows a blurred, tinted band with a hairline fades in, and the
/// compact title appears once the large title ([largeTitleExtent] tall) has
/// scrolled underneath.
class BisoPageHeader extends StatefulWidget {
  const BisoPageHeader({
    super.key,
    required this.offset,
    required this.largeTitleExtent,
    this.title,
    this.showLargeTitle = true,
    this.leading,
    this.actions = const [],
    this.search,
    this.overImage = false,
  });

  final ValueListenable<double> offset;
  final ValueListenable<double> largeTitleExtent;
  final String? title;
  final bool showLargeTitle;
  final Widget? leading;
  final List<BisoHeaderAction> actions;
  final BisoHeaderSearch? search;
  final bool overImage;

  @override
  State<BisoPageHeader> createState() => _BisoPageHeaderState();
}

class _BisoPageHeaderState extends State<BisoPageHeader> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.search?.initialQuery ?? '',
  );
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  late bool _searching = _controller.text.isNotEmpty;

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _searching = true);
    widget.search?.onExpansionChanged?.call(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searching) _focusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _debounce?.cancel();
    _focusNode.unfocus();
    _controller.clear();
    setState(() => _searching = false);
    widget.search?.onChanged('');
    widget.search?.onExpansionChanged?.call(false);
  }

  void _onQueryChanged(String value) {
    final search = widget.search!;
    _debounce?.cancel();
    if (value.isEmpty || search.debounce == Duration.zero) {
      search.onChanged(value);
    } else {
      _debounce = Timer(search.debounce, () => search.onChanged(value));
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final searching = _searching && widget.search != null;
    return PopScope(
      canPop: !searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && searching) _closeSearch();
      },
      child: ListenableBuilder(
        listenable: Listenable.merge([
          widget.offset,
          widget.largeTitleExtent,
        ]),
        builder: (context, _) {
          final offset = widget.offset.value;
          double fadeAfter(double start) => media.disableAnimations
              ? (offset > start ? 1.0 : 0.0)
              : ((offset - start) / _fadeDistance).clamp(0.0, 1.0);
          final band = fadeAfter(0);
          final titleOpacity = widget.overImage
              ? band
              : widget.showLargeTitle
              ? fadeAfter(widget.largeTitleExtent.value - 8)
              : 1.0;
          final onImage = widget.overImage && band < 0.5;
          final palette = BisoPalette.of(context);
          final foreground = onImage ? Colors.white : palette.ink;
          final darkContent =
              onImage || Theme.of(context).brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: darkContent
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
            child: SizedBox(
              key: const ValueKey('biso-page-header'),
              height: media.padding.top + kBisoHeaderHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (band > 0)
                    _HeaderBand(amount: band, opaque: media.highContrast),
                  if (widget.overImage) _HeaderImageScrim(band: band),
                  Padding(
                    padding: EdgeInsets.fromLTRB(12, media.padding.top, 12, 2),
                    child: IconTheme.merge(
                      data: IconThemeData(color: foreground),
                      child: AnimatedSwitcher(
                        duration: media.disableAnimations
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        child: searching
                            ? _searchRow(context)
                            : _toolbar(context, foreground, titleOpacity),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _toolbar(BuildContext context, Color foreground, double titleOpacity) {
    final buttons = <Widget>[
      for (final action in widget.actions)
        BisoCapsuleButton(
          icon: action.icon,
          tooltip: action.tooltip,
          onPressed: action.onPressed,
          badge: action.badge,
          color: foreground,
        ),
      if (widget.search != null)
        BisoCapsuleButton(
          icon: CupertinoIcons.search,
          tooltip: MaterialLocalizations.of(context).searchFieldLabel,
          onPressed: _openSearch,
          color: foreground,
        ),
    ];
    return NavigationToolbar(
      key: const ValueKey('biso-header-toolbar'),
      centerMiddle: true,
      middleSpacing: 12,
      leading: widget.leading == null
          ? null
          : Align(widthFactor: 1, child: widget.leading),
      middle: widget.title == null
          ? null
          : Opacity(
              opacity: titleOpacity,
              child: ExcludeSemantics(
                excluding: titleOpacity < 0.5,
                child: Text(
                  widget.title!,
                  key: const ValueKey('biso-compact-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontSize: 17,
                    color: foreground,
                  ),
                ),
              ),
            ),
      trailing: buttons.isEmpty
          ? null
          : Align(
              widthFactor: 1,
              child: BisoGlassCapsule(children: buttons),
            ),
    );
  }

  Widget _searchRow(BuildContext context) {
    final palette = BisoPalette.of(context);
    final search = widget.search!;
    return Row(
      key: const ValueKey('biso-header-search'),
      children: [
        Expanded(
          child: BisoChrome(
            radius: 24,
            child: SizedBox(
              height: 48,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                onChanged: _onQueryChanged,
                onSubmitted: (value) {
                  _debounce?.cancel();
                  search.onChanged(value);
                  _focusNode.unfocus();
                },
                textInputAction: TextInputAction.search,
                textAlignVertical: TextAlignVertical.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: palette.ink),
                decoration: InputDecoration(
                  hintText: search.hintText,
                  prefixIcon: Icon(
                    CupertinoIcons.search,
                    size: 20,
                    color: palette.muted,
                  ),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        BisoGlassCapsule(
          children: [
            BisoCapsuleButton(
              icon: CupertinoIcons.xmark,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: _closeSearch,
              color: palette.ink,
            ),
          ],
        ),
      ],
    );
  }
}

/// A faint top-to-bottom black scrim drawn only on `overImage` pages, behind
/// the header's controls, so the glass back button and actions stay legible
/// on a bright photo before the blurred [_HeaderBand] has faded in. It fades
/// out as the band fades in ([band] 1 → the band alone is enough contrast),
/// and it is a plain gradient, never a [BackdropFilter].
class _HeaderImageScrim extends StatelessWidget {
  const _HeaderImageScrim({required this.band});

  final double band;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      key: const ValueKey('biso-header-image-scrim'),
      opacity: (1 - band).clamp(0.0, 1.0),
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.35),
                Colors.black.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderBand extends StatelessWidget {
  const _HeaderBand({required this.amount, required this.opaque});

  final double amount;
  final bool opaque;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final darkTheme = Theme.of(context).brightness == Brightness.dark;
    final tintAlpha = opaque ? 1.0 : (darkTheme ? 0.72 : 0.78);
    final tint = DecoratedBox(
      decoration: BoxDecoration(
        color: palette.paper.withValues(alpha: tintAlpha * amount),
        border: Border(
          bottom: BorderSide(
            color: palette.hairline.withValues(alpha: amount),
            width: 0.5,
          ),
        ),
      ),
    );
    return KeyedSubtree(
      key: const ValueKey('biso-header-band'),
      child: opaque
          ? tint
          : ClipRect(
              child: BackdropFilter.grouped(
                filter: ImageFilter.blur(
                  sigmaX: 20 * amount,
                  sigmaY: 20 * amount,
                ),
                child: tint,
              ),
            ),
    );
  }
}
