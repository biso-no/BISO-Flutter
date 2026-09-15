import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:native_liquid_glass_flutter/native_liquid_glass_flutter.dart';

/// The only third-party material boundary. Content cards never create native
/// views or capture the Flutter scene. iOS owns just the floating material.
class BisoChrome extends StatelessWidget {
  const BisoChrome({
    super.key,
    required this.child,
    this.radius = 32,
    this.onImage = false,
  });

  final Widget child;
  final double radius;

  /// True while this chrome floats over a photo with no header band behind
  /// it yet (see `BisoPageHeader`'s `onImage`). The native liquid-glass
  /// surface lightens itself over bright content, so a scrim drawn behind
  /// the header can't guarantee contrast — the capsule itself must darken.
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        !MediaQuery.highContrastOf(context)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: LiquidGlassSurfaceBackdrop(
                configuration: LiquidGlassConfiguration(
                  role: LiquidGlassSurfaceRole.chrome,
                  cornerRadius: radius,
                  tintColor: onImage ? Colors.black : scheme.surface,
                  tintOpacity: onImage ? 0.3 : 0,
                  strokeOpacity: 0,
                  shadowOpacity: 0,
                ),
                fallbackColor: scheme.surface,
                borderRadius: BorderRadius.circular(radius),
                useNative: true,
              ),
            ),
            child,
          ],
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        // The fallback (non-native, or high contrast) surface: an opaque
        // `scheme.surface` here would be white-on-white against a photo, so
        // paint a dark translucent fill instead while onImage.
        color: onImage
            ? Colors.black.withValues(alpha: 0.35)
            : scheme.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
