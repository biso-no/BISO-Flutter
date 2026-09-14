import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../biso/biso.dart';

/// A settings row toggling one notification preference. [onChanged] may be
/// null while the underlying async state is loading or failed, which renders
/// a disabled switch.
Widget buildNotificationTile({
  required IconData icon,
  BisoAccent accent = BisoAccent.neutral,
  required String title,
  required String subtitle,
  required bool isEnabled,
  required ValueChanged<bool>? onChanged,
}) {
  return BisoListRow(
    leading: BisoIconTile(icon: icon, accent: accent),
    title: title,
    subtitle: subtitle,
    trailing: Switch.adaptive(value: isEnabled, onChanged: onChanged),
  );
}

/// A settings row shown in place of [buildNotificationTile] while its data is
/// loading.
Widget buildLoadingTile(String title) {
  return BisoListRow(
    leading: const SizedBox(
      width: 32,
      height: 32,
      child: Padding(
        padding: EdgeInsets.all(4),
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
    title: title,
  );
}

/// A settings row shown in place of [buildNotificationTile] when its data
/// failed to load. Unlike [BisoListRow]'s `subtitle` (capped at two lines),
/// [message] renders in full — error text is not curated copy, and clipping
/// it can hide the one detail that explains what went wrong.
Widget buildErrorTile(String title, String message) {
  return Builder(
    builder: (context) {
      final palette = BisoPalette.of(context);
      final text = Theme.of(context).textTheme;
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BisoIconTile(icon: CupertinoIcons.exclamationmark_circle),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: text.titleMedium?.copyWith(color: palette.error)),
                  const SizedBox(height: 2),
                  Text(message, style: text.bodyMedium?.copyWith(color: palette.muted)),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
