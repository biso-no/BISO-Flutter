import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/entur_models.dart';
import '../../../providers/ui/entur_provider.dart';
import '../../widgets/biso/biso.dart';

class DeparturesScreen extends ConsumerWidget {
  const DeparturesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = BisoPalette.of(context);
    final theme = Theme.of(context);
    final ui = ref.watch(enturUiProvider);
    final stopPlacesAsync = ref.watch(stopPlacesForCampusProvider);

    return BisoPage(
      title: 'Departures',
      leading: BisoBackButton(
        onPressed: () =>
            NavigationUtils.safeGoBack(context, fallbackRoute: '/explore'),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _TransitFilterChip(
                      selected: ui.showBus,
                      icon: CupertinoIcons.bus,
                      label: 'Bus',
                      onTap: () =>
                          ref.read(enturUiProvider.notifier).toggleBus(),
                    ),
                    const SizedBox(width: 12),
                    _TransitFilterChip(
                      selected: ui.showMetro,
                      icon: CupertinoIcons.tram_fill,
                      label: 'Metro',
                      onTap: () =>
                          ref.read(enturUiProvider.notifier).toggleMetro(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                stopPlacesAsync.when(
                  data: (stops) => _stopPicker(context, ref, ui, stops),
                  loading: () => LinearProgressIndicator(
                    color: palette.link,
                    backgroundColor: palette.surfaceRaised,
                  ),
                  error: (_, _) => Text(
                    'Failed to load stop places',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        ..._departureSlivers(
          board: ui.board,
          showBus: ui.showBus,
          showMetro: ui.showMetro,
        ),
      ],
    );
  }
}

/// A Bus/Metro toggle. The shared `ChipThemeData` (premium_theme.dart) only
/// ever applies `labelStyle`'s fixed `palette.ink` to the label — Flutter's
/// current `RawChip` resolves label color from `labelStyle` alone and does
/// not use `secondaryLabelStyle` for the selected state — so a selected chip
/// would otherwise render `palette.ink` text on the `palette.primary`
/// background it also picks for selection, which is illegible on light
/// (navy-on-navy). This chip supplies its own state-aware color instead of
/// relying on the shared theme.
class _TransitFilterChip extends StatelessWidget {
  const _TransitFilterChip({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final color = selected ? palette.onPrimary : palette.ink;
    return FilterChip(
      selected: selected,
      onSelected: (_) => onTap(),
      avatar: Icon(icon, size: 18, color: color),
      label: Text(label),
      labelStyle: Theme.of(
        context,
      ).textTheme.labelMedium?.copyWith(color: color),
    );
  }
}

/// The stop-place picker: a dropdown grouped by display name, mirroring the
/// original screen's selection logic exactly (including the post-frame
/// default selection), restyled onto [BisoFormRow].
Widget _stopPicker(
  BuildContext context,
  WidgetRef ref,
  EnturUiState ui,
  List<StopPlaceModel> stops,
) {
  final palette = BisoPalette.of(context);
  if (stops.isEmpty) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        'No stop places configured for this campus',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: palette.muted),
      ),
    );
  }

  // Group stops by display name
  final Map<String, List<StopPlaceModel>> groupedByName = {};
  for (final s in stops) {
    final key = (s.name ?? s.stopPlaceId).trim();
    groupedByName.putIfAbsent(key, () => <StopPlaceModel>[]).add(s);
  }
  final List<String> groupNames = groupedByName.keys.toList()..sort();

  // Determine selected group based on current selected stopPlaceId
  String selectedGroupName;
  if (ui.selectedStopPlaceId == null) {
    selectedGroupName = groupNames.first;
    // Initialize selection to the first stop of the first group
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final firstId = groupedByName[selectedGroupName]!.first.stopPlaceId;
      ref.read(enturUiProvider.notifier).setStopPlace(firstId);
    });
  } else {
    final foundEntry = groupedByName.entries.firstWhere(
      (e) => e.value.any((s) => s.stopPlaceId == ui.selectedStopPlaceId),
      orElse: () =>
          MapEntry(groupNames.first, groupedByName[groupNames.first]!),
    );
    selectedGroupName = foundEntry.key;
  }

  return BisoFormRow(
    label: 'Stop Place',
    child: DropdownButtonFormField<String>(
      initialValue: selectedGroupName,
      decoration: bisoInputDecoration(context),
      items: groupNames.map((name) {
        final count = groupedByName[name]!.length;
        final label = count > 1 ? '$name ($count stops)' : name;
        return DropdownMenuItem<String>(value: name, child: Text(label));
      }).toList(),
      onChanged: (groupName) {
        if (groupName == null) return;
        final firstId = groupedByName[groupName]!.first.stopPlaceId;
        ref.read(enturUiProvider.notifier).setStopPlace(firstId);
      },
    ),
  );
}

/// The departure list, or the shared "no departures" empty state — used both
/// while no board has loaded yet and once the current filters leave nothing
/// to show, matching the original screen's single "No departures" message
/// for both cases.
List<Widget> _departureSlivers({
  required EnturDepartureBoard? board,
  required bool showBus,
  required bool showMetro,
}) {
  final calls = board?.calls ?? const <EnturEstimatedCall>[];
  final filtered = calls.where((c) {
    if (c.transportMode == 'bus') return showBus;
    if (c.transportMode == 'metro') return showMetro;
    return true;
  }).toList();

  if (filtered.isEmpty) {
    return [
      const SliverFillRemaining(
        hasScrollBody: false,
        child: BisoEmptyState(
          icon: CupertinoIcons.tram_fill,
          accent: BisoAccent.blue,
          title: 'No departures',
        ),
      ),
    ];
  }

  return [
    SliverBisoListGroup(
      itemCount: filtered.length,
      itemBuilder: (context, index) => _DepartureRow(call: filtered[index]),
    ),
  ];
}

class _DepartureRow extends StatelessWidget {
  const _DepartureRow({required this.call});

  final EnturEstimatedCall call;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final theme = Theme.of(context);
    final now = DateTime.now();
    final diff = call.expectedDepartureTime.difference(now);
    final secondsTo = diff.inSeconds;
    final bool departed = secondsTo < -30; // give 30s grace
    final int deltaMinutes = call.expectedDepartureTime
        .difference(call.aimedDepartureTime)
        .inMinutes;
    final bool isDelayed = deltaMinutes > 0;
    final bool isMetro = call.transportMode == 'metro';

    final String valueText = departed
        ? _formatTime(call.expectedDepartureTime)
        : (secondsTo <= 30 ? 'Now' : '${diff.inMinutes} min');

    return Opacity(
      opacity: departed ? 0.6 : 1,
      child: BisoListRow(
        leading: BisoIconTile(
          icon: isMetro ? CupertinoIcons.tram_fill : CupertinoIcons.bus,
          accent: BisoAccent.blue,
        ),
        title: call.destination,
        subtitle: call.lineName.isEmpty ? null : call.lineName,
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              valueText,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: isDelayed ? palette.warning : palette.muted,
              ),
            ),
            if (call.realtime) ...[
              const SizedBox(height: 2),
              Icon(
                CupertinoIcons.dot_radiowaves_left_right,
                size: 14,
                color: palette.link,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}';
  }
}
