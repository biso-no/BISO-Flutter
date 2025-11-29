import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../providers/ui/entur_provider.dart';
import '../../../data/models/entur_models.dart';

class DeparturesScreen extends ConsumerWidget {
  const DeparturesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(enturUiProvider);
    final stopPlacesAsync = ref.watch(stopPlacesForCampusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Departures')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                FilterChip(
                  selected: ui.showBus,
                  onSelected: (_) =>
                      ref.read(enturUiProvider.notifier).toggleBus(),
                  avatar: const Icon(Icons.directions_bus, size: 18),
                  label: const Text('Bus'),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  selected: ui.showMetro,
                  onSelected: (_) =>
                      ref.read(enturUiProvider.notifier).toggleMetro(),
                  avatar: const Icon(Icons.subway, size: 18),
                  label: const Text('Metro'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            stopPlacesAsync.when(
              data: (stops) {
                if (stops.isEmpty) {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No stop places configured for this campus'),
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
                    orElse: () => MapEntry(groupNames.first, groupedByName[groupNames.first]!),
                  );
                  selectedGroupName = foundEntry.key;
                }

                return DropdownButtonFormField<String>(
                  initialValue: selectedGroupName,
                  decoration: const InputDecoration(
                    labelText: 'Stop Place',
                    border: OutlineInputBorder(),
                  ),
                  items: groupNames
                      .map((name) {
                        final count = groupedByName[name]!.length;
                        final label = count > 1 ? '$name ($count stops)' : name;
                        return DropdownMenuItem<String>(
                          value: name,
                          child: Text(label),
                        );
                      })
                      .toList(),
                  onChanged: (groupName) {
                    if (groupName == null) return;
                    final firstId = groupedByName[groupName]!.first.stopPlaceId;
                    ref.read(enturUiProvider.notifier).setStopPlace(firstId);
                  },
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Align(
                alignment: Alignment.centerLeft,
                child: Text('Failed to load stop places'),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _DepartureBoard(
                board: ui.board,
                showBus: ui.showBus,
                showMetro: ui.showMetro,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DepartureBoard extends StatelessWidget {
  final EnturDepartureBoard? board;
  final bool showBus;
  final bool showMetro;

  const _DepartureBoard({
    required this.board,
    required this.showBus,
    required this.showMetro,
  });

  @override
  Widget build(BuildContext context) {
    if (board == null) {
      return const Center(child: Text('No departures'));
    }
    final filtered = board!.calls.where((c) {
      if (c.transportMode == 'bus') return showBus;
      if (c.transportMode == 'metro') return showMetro;
      return true;
    }).toList();

    if (filtered.isEmpty) {
      return const Center(child: Text('No departures'));
    }

    return ListView.separated(
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final call = filtered[index];
        return _DepartureTile(call: call);
      },
    );
  }
}

class _DepartureTile extends StatelessWidget {
  final EnturEstimatedCall call;
  const _DepartureTile({required this.call});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final diff = call.expectedDepartureTime.difference(now);
    final secondsTo = diff.inSeconds;
    final minutesTo = diff.inMinutes.abs();
    final bool departed = secondsTo < -30; // give 30s grace
    final String subtitle = departed
        ? 'Departed $minutesTo min ago'
        : (secondsTo <= 30 ? 'Now' : 'In ${diff.inMinutes} min');
    final isMetro = call.transportMode == 'metro';
    final int deltaMinutes = call.expectedDepartureTime
        .difference(call.aimedDepartureTime)
        .inMinutes;
    final bool isDelayed = deltaMinutes > 0;

    return Opacity(
      opacity: departed ? 0.6 : 1,
      child: Container(
      decoration: BoxDecoration(
        color: isMetro
            ? AppColors.subtleBlue
            : Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor:
                isMetro ? AppColors.defaultBlue : Colors.black87,
            child: Icon(
              isMetro ? Icons.subway : Icons.directions_bus,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  call.destination,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  call.lineName,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatTime(call.expectedDepartureTime),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Row(children: [
                if (call.realtime)
                  const Icon(Icons.wifi_tethering,
                      size: 14, color: AppColors.defaultBlue),
                if (call.realtime) const SizedBox(width: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ]),
              if (deltaMinutes != 0) const SizedBox(height: 6),
              if (deltaMinutes != 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDelayed
                            ? AppColors.orange3
                            : AppColors.green3,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isDelayed
                            ? 'Delayed +${deltaMinutes}m'
                            : 'Early ${deltaMinutes.abs()}m',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: isDelayed
                                  ? AppColors.orange10
                                  : AppColors.green10,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Scheduled ${_formatTime(call.aimedDepartureTime)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.gray600,
                            decoration: TextDecoration.lineThrough,
                          ),
                    ),
                  ],
                ),
            ],
          ),
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