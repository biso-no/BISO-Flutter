import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import '../../../core/theme/biso_colors.dart';

/// Feed card image with an icon placeholder while loading or on error.
class BisoFeedImage extends StatelessWidget {
  const BisoFeedImage({
    super.key,
    this.url,
    required this.height,
    required this.fallback,
  });
  final String? url;
  final double height;
  final IconData fallback;
  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    Widget placeholder() => ColoredBox(
      color: palette.surfaceRaised,
      child: Center(child: Icon(fallback, size: 32, color: palette.muted)),
    );
    return SizedBox(
      height: height,
      width: double.infinity,
      child: url?.isNotEmpty == true
          ? CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              memCacheWidth: 1000,
              placeholder: (_, _) => placeholder(),
              errorWidget: (_, _, _) => placeholder(),
            )
          : placeholder(),
    );
  }
}
