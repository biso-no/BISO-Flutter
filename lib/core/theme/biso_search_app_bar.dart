import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'biso_chrome.dart';

/// Search replaces the existing toolbar, preserving the content viewport.
/// No search history is stored. Closing also cancels pending query delivery.
class BisoSearchAppBar extends StatefulWidget implements PreferredSizeWidget {
  const BisoSearchAppBar({
    super.key,
    required this.title,
    required this.hintText,
    required this.onChanged,
    this.leading,
    this.actions = const [],
    this.controller,
    this.initialQuery = '',
    this.initiallyExpanded = false,
    this.searchEnabled = true,
    this.onExpansionChanged,
    this.debounce = const Duration(milliseconds: 350),
    this.titleStyle,
    this.toolbarHeight = 72,
  });

  final String title;
  final String hintText;
  final ValueChanged<String> onChanged;
  final Widget? leading;
  final List<Widget> actions;
  final TextEditingController? controller;
  final String initialQuery;
  final bool initiallyExpanded;
  final bool searchEnabled;
  final ValueChanged<bool>? onExpansionChanged;
  final Duration debounce;
  final TextStyle? titleStyle;
  final double toolbarHeight;

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight);

  @override
  State<BisoSearchAppBar> createState() => _BisoSearchAppBarState();
}

class _BisoSearchAppBarState extends State<BisoSearchAppBar> {
  late final _controller =
      widget.controller ?? TextEditingController(text: widget.initialQuery);
  final _focusNode = FocusNode();
  Timer? _debounce;
  late bool _expanded = widget.initiallyExpanded || _controller.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (widget.initiallyExpanded) _focusAfterBuild();
  }

  void _focusAfterBuild() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _expanded) _focusNode.requestFocus();
  });

  void _open() {
    setState(() => _expanded = true);
    widget.onExpansionChanged?.call(true);
    _focusAfterBuild();
  }

  void _close() {
    _debounce?.cancel();
    _focusNode.unfocus();
    _controller.clear();
    setState(() => _expanded = false);
    widget.onChanged('');
    widget.onExpansionChanged?.call(false);
  }

  void _query(String value) {
    _debounce?.cancel();
    if (value.isEmpty || widget.debounce == Duration.zero) {
      widget.onChanged(value);
    } else {
      _debounce = Timer(widget.debounce, () => widget.onChanged(value));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = MaterialLocalizations.of(context);
    final expanded = _expanded && widget.searchEnabled;
    final leading =
        widget.leading ??
        (Navigator.of(context).canPop() ? const BackButton() : null);
    return PopScope(
      canPop: !expanded,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && expanded) _close();
      },
      child: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: widget.toolbarHeight,
        titleSpacing: 16,
        title: AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: AnimatedBuilder(
              animation: animation,
              child: child,
              builder: (context, child) => ClipRect(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  widthFactor: animation.value,
                  child: child,
                ),
              ),
            ),
          ),
          child: expanded
              ? Row(
                  key: const ValueKey('biso-search-expanded'),
                  children: [
                    Expanded(
                      child: BisoChrome(
                        radius: 26,
                        child: SizedBox(
                          height: 52,
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            onChanged: _query,
                            onSubmitted: (value) {
                              _debounce?.cancel();
                              widget.onChanged(value);
                              _focusNode.unfocus();
                            },
                            textInputAction: TextInputAction.search,
                            textAlignVertical: TextAlignVertical.center,
                            style: Theme.of(context).textTheme.bodyLarge,
                            decoration: InputDecoration(
                              hintText: widget.hintText,
                              prefixIcon: const Icon(CupertinoIcons.search),
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
                    _GlassButton(
                      icon: CupertinoIcons.xmark,
                      tooltip: strings.closeButtonTooltip,
                      onPressed: _close,
                    ),
                  ],
                )
              : Row(
                  key: const ValueKey('biso-search-collapsed'),
                  children: [
                    ?leading,
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: widget.titleStyle,
                      ),
                    ),
                    ...widget.actions,
                    if (widget.searchEnabled) ...[
                      const SizedBox(width: 8),
                      _GlassButton(
                        icon: CupertinoIcons.search,
                        tooltip: strings.searchFieldLabel,
                        onPressed: _open,
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => BisoChrome(
    radius: 26,
    child: SizedBox.square(
      dimension: 52,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 24),
      ),
    ),
  );
}
