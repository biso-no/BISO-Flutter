import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/biso_colors.dart';
import '../../../generated/l10n/app_localizations.dart';
import 'biso_icon_tile.dart';

class BisoEmptyState extends StatelessWidget {
  const BisoEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.accent = BisoAccent.neutral,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final BisoAccent accent;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BisoIconTile(icon: icon, accent: accent, size: 56),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: text.titleLarge?.copyWith(color: palette.ink),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: palette.muted),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

class BisoErrorState extends StatelessWidget {
  const BisoErrorState({super.key, this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BisoEmptyState(
      icon: CupertinoIcons.exclamationmark_triangle,
      title:
          message ?? l10n?.somethingWentWrongMessage ?? 'Something went wrong',
      action: FilledButton(
        onPressed: onRetry,
        child: Text(l10n?.retry ?? 'Retry'),
      ),
    );
  }
}

enum _SkeletonKind { rows, grid, card }

/// Static placeholders shaped like the content they stand in for.
class BisoSkeleton extends StatelessWidget {
  const BisoSkeleton.rows({super.key, this.count = 6})
    : _kind = _SkeletonKind.rows;
  const BisoSkeleton.grid({super.key, this.count = 6})
    : _kind = _SkeletonKind.grid;
  const BisoSkeleton.card({super.key}) : count = 1, _kind = _SkeletonKind.card;

  final int count;
  final _SkeletonKind _kind;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    Widget block({double? width, required double height, double radius = 8}) =>
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: BorderRadius.circular(radius),
          ),
        );

    Widget row() => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          block(width: 32, height: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                block(width: 180, height: 12, radius: 6),
                const SizedBox(height: 8),
                block(width: 120, height: 10, radius: 5),
              ],
            ),
          ),
        ],
      ),
    );

    Widget card() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        block(height: 160, radius: 18),
        const SizedBox(height: 12),
        block(width: 200, height: 14, radius: 7),
        const SizedBox(height: 8),
        block(width: 120, height: 10, radius: 5),
      ],
    );

    final Widget child = switch (_kind) {
      _SkeletonKind.rows => DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(children: [for (var i = 0; i < count; i++) row()]),
      ),
      _SkeletonKind.grid => Column(
        children: [
          for (var i = 0; i < count; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Expanded(child: card()),
                  const SizedBox(width: 12),
                  Expanded(child: i + 1 < count ? card() : const SizedBox()),
                ],
              ),
            ),
        ],
      ),
      _SkeletonKind.card => card(),
    };

    return Semantics(
      label: AppLocalizations.of(context)?.loadingMessage ?? 'Loading',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: child,
        ),
      ),
    );
  }
}
