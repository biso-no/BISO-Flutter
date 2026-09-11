import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/biso_colors.dart';

const _groupRadius = 20.0;

/// A titled block of content, such as a grouped list.
class BisoSection extends StatelessWidget {
  const BisoSection({
    super.key,
    this.title,
    this.action,
    this.footer,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 24, 16, 0),
  });

  final String? title;

  /// A trailing control beside the title, such as "See all" or a menu.
  final Widget? action;
  final String? footer;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title!,
                        style: text.headlineSmall?.copyWith(color: palette.ink),
                      ),
                    ),
                  ),
                  ?action,
                ],
              ),
            ),
          child,
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                footer!,
                style: text.bodySmall?.copyWith(color: palette.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class BisoRowDivider extends StatelessWidget {
  const BisoRowDivider({super.key, this.indent = 60});

  final double indent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.only(start: indent),
    child: Divider(
      height: 0.5,
      thickness: 0.5,
      color: BisoPalette.of(context).hairline,
    ),
  );
}

/// Rows on one rounded surface, separated by inset hairlines. For long or
/// unbounded lists use [SliverBisoListGroup].
class BisoListGroup extends StatelessWidget {
  const BisoListGroup({
    super.key,
    required this.children,
    this.dividerIndent = 60,
  });

  final List<Widget> children;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) => Material(
    color: BisoPalette.of(context).surface,
    borderRadius: BorderRadius.circular(_groupRadius),
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) BisoRowDivider(indent: dividerIndent),
          children[i],
        ],
      ],
    ),
  );
}

/// A lazily built [BisoListGroup] for use inside a CustomScrollView.
class SliverBisoListGroup extends StatelessWidget {
  const SliverBisoListGroup({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.dividerIndent = 60,
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 0),
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double dividerIndent;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final surface = BisoPalette.of(context).surface;
    return SliverPadding(
      padding: margin,
      sliver: SliverList.separated(
        itemCount: itemCount,
        separatorBuilder: (context, _) => ColoredBox(
          color: surface,
          child: BisoRowDivider(indent: dividerIndent),
        ),
        itemBuilder: (context, index) {
          final first = index == 0;
          final last = index == itemCount - 1;
          return ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(first ? _groupRadius : 0),
              bottom: Radius.circular(last ? _groupRadius : 0),
            ),
            child: Material(color: surface, child: itemBuilder(context, index)),
          );
        },
      ),
    );
  }
}

class BisoListRow extends StatelessWidget {
  const BisoListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.value,
    this.trailing,
    this.showChevron,
    this.onTap,
    this.destructive = false,
    this.titleMaxLines = 2,
  });

  final String title;
  final String? subtitle;

  /// Usually a BisoIconTile or an avatar.
  final Widget? leading;

  /// Right-aligned secondary text, such as a setting's current value.
  final String? value;
  final Widget? trailing;

  /// Defaults to true when the row is tappable and has no [trailing].
  final bool? showChevron;
  final VoidCallback? onTap;
  final bool destructive;
  final int titleMaxLines;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    final chevron = showChevron ?? (onTap != null && trailing == null);
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 10),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: titleMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(
                          color: destructive ? palette.error : palette.ink,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium?.copyWith(
                              color: palette.muted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: text.bodyLarge?.copyWith(color: palette.muted),
                    ),
                  ),
                ],
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
                if (chevron) ...[
                  const SizedBox(width: 8),
                  Icon(
                    CupertinoIcons.chevron_forward,
                    size: 17,
                    color: palette.muted,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
