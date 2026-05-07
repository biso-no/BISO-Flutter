import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../../core/logging/print_migration.dart';

import '../../core/constants/app_colors.dart';
import '../../core/theme/biso_glass.dart';
import '../../providers/weather/weather_provider.dart';
import '../../data/models/campus_model.dart';
import '../../providers/campus/campus_provider.dart';

class CampusSwitcher extends ConsumerWidget {
  final bool showFullScreen;
  final VoidCallback? onCampusChanged;

  const CampusSwitcher({
    super.key,
    this.showFullScreen = false,
    this.onCampusChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buildStart = DateTime.now();
    final selectedCampus = ref.watch(filterCampusProvider);
    final allCampusesAsync = ref.watch(switcherCampusesProvider);
    final isInitialized = ref.watch(campusInitializedProvider);
    final theme = Theme.of(context);

    logInfo(
      'CampusSwitcher.build: start',
      context: {
        'initialized': isInitialized,
        'selected_id': selectedCampus.id,
        'selected_name': selectedCampus.name,
        'allCampuses_state': allCampusesAsync.hasValue
            ? 'data'
            : (allCampusesAsync.hasError ? 'error' : 'loading'),
      },
    );

    if (showFullScreen) {
      return allCampusesAsync.when(
        loading: () {
          logInfo('CampusSwitcher.fullScreen: loading');
          return const Center(child: CircularProgressIndicator());
        },
        error: (e, _) {
          logError('CampusSwitcher.fullScreen: error', error: e);
          return Center(child: Text('Failed to load campuses'));
        },
        data: (allCampuses) {
          logInfo(
            'CampusSwitcher.fullScreen: data',
            context: {
              'campus_count': allCampuses.length,
              'elapsed_ms_since_build': DateTime.now()
                  .difference(buildStart)
                  .inMilliseconds,
            },
          );
          return _FullScreenCampusSwitcher(
            selectedCampus: selectedCampus,
            allCampuses: allCampuses,
            onCampusChanged: onCampusChanged,
          );
        },
      );
    }

    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: () => _showCampusSwitcherModal(context),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.midNavy.withValues(alpha: 0.55)
              : AppColors.subtleBlue,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark
                ? AppColors.skyBlue.withValues(alpha: 0.3)
                : AppColors.defaultBlue.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: _getCampusColor(selectedCampus.id),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  selectedCampus.name[0],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedCampus.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.skyBlue : AppColors.defaultBlue,
                  ),
                ),
                Consumer(
                  builder: (context, ref, _) {
                    final weatherAsync = ref.watch(
                      campusWeatherProvider(selectedCampus.name),
                    );
                    return weatherAsync.when(
                      data: (w) => w == null
                          ? const SizedBox.shrink()
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  w.icon,
                                  style: const TextStyle(fontSize: 10),
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '${w.temperature.round()}°',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: isDark
                                        ? AppColors.mist
                                        : AppColors.onSurfaceVariant,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                      loading: () => const SizedBox(
                        height: 12,
                        width: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      error: (err, st) => const SizedBox.shrink(),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.expand_more,
              size: 16,
              color: isDark ? AppColors.skyBlue : AppColors.defaultBlue,
            ),
          ],
        ),
      ),
    );
  }

  void _showCampusSwitcherModal(BuildContext context) {
    logInfo('CampusSwitcher: open modal');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Consumer(
        builder: (context, ref, child) {
          final selectedCampus = ref.watch(filterCampusProvider);
          final allCampusesAsync = ref.watch(switcherCampusesProvider);
          return allCampusesAsync.when(
            loading: () {
              logInfo('CampusSwitcher.modal: loading');
              return const Center(child: CircularProgressIndicator());
            },
            error: (e, _) {
              logError('CampusSwitcher.modal: error', error: e);
              return Center(child: Text('Failed to load campuses'));
            },
            data: (allCampuses) {
              logInfo(
                'CampusSwitcher.modal: data',
                context: {
                  'campus_count': allCampuses.length,
                  'selected_id': selectedCampus.id,
                },
              );
              return _CampusSwitcherModal(
                selectedCampus: selectedCampus,
                allCampuses: allCampuses,
                onCampusSelected: (campus) {
                  logInfo(
                    'CampusSwitcher.modal: select campus',
                    context: {
                      'selected_id': campus.id,
                      'selected_name': campus.name,
                    },
                  );
                  ref
                      .read(filterCampusStateProvider.notifier)
                      .selectFilterCampus(campus);
                  Navigator.pop(context);
                  onCampusChanged?.call();
                },
              );
            },
          );
        },
      ),
    );
  }

  Color _getCampusColor(String campusId) {
    switch (campusId) {
      case '1': // Oslo
        return AppColors.defaultBlue;
      case '2': // Bergen
        return AppColors.green9;
      case '3': // Trondheim
        return AppColors.purple9;
      case '4': // Stavanger
        return AppColors.orange9;
      default:
        return AppColors.gray400;
    }
  }
}

class _FullScreenCampusSwitcher extends StatelessWidget {
  final CampusModel selectedCampus;
  final List<CampusModel> allCampuses;
  final VoidCallback? onCampusChanged;

  const _FullScreenCampusSwitcher({
    required this.selectedCampus,
    required this.allCampuses,
    this.onCampusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Campus'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Consumer(
        builder: (context, ref, child) {
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: allCampuses.length,
            itemBuilder: (context, index) {
              final campus = allCampuses[index];
              final isSelected = campus.id == selectedCampus.id;

              return _CampusCard(
                campus: campus,
                isSelected: isSelected,
                onTap: () {
                  ref
                      .read(filterCampusStateProvider.notifier)
                      .selectFilterCampus(campus);
                  Navigator.pop(context);
                  onCampusChanged?.call();
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _CampusSwitcherModal extends StatelessWidget {
  final CampusModel selectedCampus;
  final List<CampusModel> allCampuses;
  final Function(CampusModel) onCampusSelected;

  const _CampusSwitcherModal({
    required this.selectedCampus,
    required this.allCampuses,
    required this.onCampusSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return BisoGlassCard(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: EdgeInsets.zero,
      borderRadius: 24,
      quality: GlassQuality.standard,
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.gray300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Text(
                  'Select Campus',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? AppColors.onSurfaceDark
                        : AppColors.onSurface,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close,
                    color: isDark
                        ? AppColors.onSurfaceDark
                        : AppColors.onSurface,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: isDark
                        ? AppColors.surfaceVariantDark
                        : AppColors.surfaceVariant,
                    foregroundColor: isDark
                        ? AppColors.onSurfaceVariantDark
                        : AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // Campus List
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: allCampuses.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final campus = allCampuses[index];
                final isSelected = campus.id == selectedCampus.id;

                return _CampusModalCard(
                  campus: campus,
                  isSelected: isSelected,
                  onTap: () => onCampusSelected(campus),
                );
              },
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _CampusCard extends StatelessWidget {
  final CampusModel campus;
  final bool isSelected;
  final VoidCallback onTap;

  const _CampusCard({
    required this.campus,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: Theme.of(context).colorScheme.surface,
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _getCampusColor(campus.id).withValues(alpha: 0.1),
                _getCampusColor(campus.id).withValues(alpha: 0.3),
              ],
            ),
          ),
          child: Stack(
            children: [
              // Background pattern or image placeholder
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _getCampusColor(campus.id).withValues(alpha: 0.1),
                        _getCampusColor(campus.id).withValues(alpha: 0.2),
                      ],
                    ),
                  ),
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _getCampusColor(campus.id),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              campus.name[0],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (isSelected)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.defaultBlue,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Selected',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    Text(
                      campus.name,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _getCampusColor(campus.id),
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      _extractAddress(campus.location),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),

                    const Spacer(),

                    // Stats row
                    Row(
                      children: [
                        _StatBadge(
                          icon: Icons.people,
                          value:
                              '${(campus.stats.studentCount / 1000).toStringAsFixed(1)}k',
                          label: 'Students',
                        ),
                        const SizedBox(width: 16),
                        _StatBadge(
                          icon: Icons.event,
                          value: campus.stats.activeEvents.toString(),
                          label: 'Events',
                        ),
                        const Spacer(),
                        if (campus.weather != null)
                          Row(
                            children: [
                              Text(
                                campus.weather!.icon,
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${campus.weather!.temperature.round()}°',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          )
                        else
                          const SizedBox.shrink(),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getCampusColor(String campusId) {
    switch (campusId) {
      case '1': // Oslo
        return AppColors.defaultBlue;
      case '2': // Bergen
        return AppColors.green9;
      case '3': // Trondheim
        return AppColors.purple9;
      case '4': // Stavanger
        return AppColors.orange9;
      default:
        return AppColors.gray400;
    }
  }
}

class _CampusModalCard extends StatelessWidget {
  final CampusModel campus;
  final bool isSelected;
  final VoidCallback onTap;

  const _CampusModalCard({
    required this.campus,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                    ? AppColors.subtleBlue.withValues(alpha: 0.2)
                    : AppColors.subtleBlue)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.defaultBlue : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _getCampusColor(campus.id),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  campus.name[0],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    campus.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.onSurfaceDark
                          : AppColors.onSurface,
                    ),
                  ),
                  if (campus.location.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      campus.location,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? AppColors.onSurfaceVariantDark
                            : AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            if (isSelected)
              Icon(Icons.check_circle, color: AppColors.defaultBlue, size: 24),
          ],
        ),
      ),
    );
  }

  Color _getCampusColor(String campusId) {
    switch (campusId) {
      case '1': // Oslo
        return AppColors.defaultBlue;
      case '2': // Bergen
        return AppColors.green9;
      case '3': // Trondheim
        return AppColors.purple9;
      case '4': // Stavanger
        return AppColors.orange9;
      default:
        return AppColors.gray400;
    }
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatBadge({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Helper function to extract address from location data
String _extractAddress(String location) {
  // If it looks like JSON, try to parse it
  if (location.startsWith('{') && location.endsWith('}')) {
    try {
      final Map<String, dynamic> locationJson = jsonDecode(location);
      return locationJson['address'] ?? location;
    } catch (e) {
      // If parsing fails, return original
    }
  }
  return location;
}
