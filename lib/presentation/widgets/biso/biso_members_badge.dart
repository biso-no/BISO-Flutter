import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/biso_colors.dart';

/// Marks something — a product, an event — as for BISO members only.
///
/// Gold, the membership accent, with its own fixed glyph color so it reads the
/// same over a photo as over a card surface: it is laid over product images in
/// lists, where there is no room for a line of text.
class BisoMembersBadge extends StatelessWidget {
  const BisoMembersBadge({super.key, this.label = 'Members only'});

  final String label;

  @override
  Widget build(BuildContext context) {
    const accent = BisoAccent.gold;
    final glyph = accent.fixedGlyph!;

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: accent.fixedFill,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.star_fill, size: 12, color: glyph),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: glyph),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
