import 'package:flutter/material.dart';

import '../../../core/theme/biso_colors.dart';

/// A floating surface for BisoPage.bottomBar, holding the page's main action.
class BisoBottomBar extends StatelessWidget {
  const BisoBottomBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: palette.hairline, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: palette.ink.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(padding: const EdgeInsets.all(12), child: child),
      ),
    );
  }
}
