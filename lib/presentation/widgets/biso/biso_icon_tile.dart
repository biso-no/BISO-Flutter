import 'package:flutter/material.dart';

import '../../../core/theme/biso_colors.dart';

/// A small rounded square carrying a category glyph, like the tiles in iOS
/// Settings. Decorative: the row it sits in carries the meaning.
class BisoIconTile extends StatelessWidget {
  const BisoIconTile({
    super.key,
    required this.icon,
    this.accent = BisoAccent.neutral,
    this.size = 32,
  });

  final IconData icon;
  final BisoAccent accent;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: accent.fill(context),
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: SizedBox.square(
        dimension: size,
        child: Icon(icon, size: size * 0.625, color: accent.glyph(context)),
      ),
    ),
  );
}
