import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:native_liquid_glass_flutter/native_liquid_glass_flutter.dart';

/// The only third-party material boundary. Content cards never create native
/// views or capture the Flutter scene. iOS owns just the floating material.
class BisoChrome extends StatelessWidget {
  const BisoChrome({super.key, required this.child, this.radius = 32});

  final Widget child;
  final double radius;

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
                  tintColor: scheme.surface,
                  tintOpacity: 0,
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
        color: scheme.surface,
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
