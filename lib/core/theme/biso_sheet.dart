import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'biso_navigation.dart';

/// Opens a modal bottom sheet that clears the floating tab bar.
///
/// [BisoNavigationScaffold] strips the bottom safe area from everything below
/// it — sheets opened from a tab's pages included — so a raw
/// `showModalBottomSheet` lets its last rows slide behind the bar. Here the
/// sheet's bottom safe area is restored to the bar's clearance, so a
/// `SafeArea` or `MediaQuery.paddingOf(context).bottom` inside the sheet
/// clears it. Outside the tab bar nothing changes.
Future<T?> showBisoSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? backgroundColor,
  ShapeBorder? shape,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: backgroundColor,
    shape: shape,
    builder: (context) => _SheetClearance(child: Builder(builder: builder)),
  );
}

class _SheetClearance extends StatelessWidget {
  const _SheetClearance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final inset = context
        .dependOnInheritedWidgetOfExactType<BisoNavigationInset>();
    if (inset == null) return child;
    final media = MediaQuery.of(context);
    // The bar hides, and its clearance drops to zero, while the keyboard is up.
    final bottom = math.max(media.padding.bottom, inset.bottom);
    return MediaQuery(
      data: media.copyWith(padding: media.padding.copyWith(bottom: bottom)),
      child: child,
    );
  }
}
