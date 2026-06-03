import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/event_segment_model.dart';
import '../../../providers/event/event_segment_provider.dart';
import '../../../providers/ui/locale_provider.dart';

/// Personalized "Your trip" card shown on the event detail view. Renders the
/// signed-in user's assigned segment(s) (bus + departure, hotel room +
/// roommates, …) for [eventId].
///
/// Renders nothing when signed out or when the user has no assigned segments,
/// consistent with the app's conditional-auth model.
class YourTripCard extends ConsumerWidget {
  final String eventId;

  const YourTripCard({required this.eventId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segmentsAsync = ref.watch(myTripProvider(eventId));
    final isNorwegian = ref.watch(localeProvider).languageCode == 'no';

    return segmentsAsync.when(
      data: (segments) {
        if (segments.isEmpty) return const SizedBox.shrink();
        return _TripCardShell(
          isNorwegian: isNorwegian,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < segments.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                _SegmentTile(
                  segment: segments[i],
                  isNorwegian: isNorwegian,
                ),
              ],
            ],
          ),
        );
      },
      loading: () => _TripCardShell(
        isNorwegian: isNorwegian,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
      // Stay silent on error: the card is supplementary and must never break
      // the event detail view.
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _TripCardShell extends StatelessWidget {
  final bool isNorwegian;
  final Widget child;

  const _TripCardShell({required this.isNorwegian, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.subtleBlue,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.accentBlue.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentBlue.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.accentBlue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.luggage,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                isNorwegian ? 'Din reise' : 'Your trip',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.strongBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _SegmentTile extends StatelessWidget {
  final EventSegment segment;
  final bool isNorwegian;

  const _SegmentTile({required this.segment, required this.isNorwegian});

  IconData _iconForKind(String kind) {
    switch (kind.toLowerCase().trim()) {
      case 'transport':
      case 'transportation':
      case 'bus':
      case 'travel':
        return Icons.directions_bus;
      case 'lodging':
      case 'hotel':
      case 'accommodation':
      case 'room':
        return Icons.hotel;
      default:
        return Icons.groups;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _metadataEntries(segment.metadata, isNorwegian);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.accentBlue.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _iconForKind(segment.kind),
                size: 20,
                color: AppColors.accentBlue,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  segment.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.strongBlue,
                  ),
                ),
              ),
            ],
          ),
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final entry in entries) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        entry.key,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Humanizes a metadata map into ordered, displayable key/value rows.
  static List<MapEntry<String, String>> _metadataEntries(
    Map<String, dynamic> metadata,
    bool isNorwegian,
  ) {
    final result = <MapEntry<String, String>>[];
    for (final entry in metadata.entries) {
      final value = _formatValue(entry.value);
      if (value.isEmpty) continue;
      result.add(MapEntry(_humanizeKey(entry.key, isNorwegian), value));
    }
    return result;
  }

  /// Maps known keys to friendly labels; falls back to a title-cased version of
  /// the raw key for anything unrecognized.
  static String _humanizeKey(String key, bool isNorwegian) {
    final normalized = key.toLowerCase().trim();
    final labels = isNorwegian ? _labelsNo : _labelsEn;
    final mapped = labels[normalized];
    if (mapped != null) return mapped;
    return _titleCase(key);
  }

  static const Map<String, String> _labelsEn = {
    'departure_time': 'Departure',
    'departure': 'Departure',
    'pickup_location': 'Pickup',
    'pickup': 'Pickup',
    'hotel': 'Hotel',
    'room_number': 'Room',
    'room': 'Room',
    'schedule': 'Schedule',
    'notes': 'Notes',
  };

  static const Map<String, String> _labelsNo = {
    'departure_time': 'Avgang',
    'departure': 'Avgang',
    'pickup_location': 'Henting',
    'pickup': 'Henting',
    'hotel': 'Hotell',
    'room_number': 'Rom',
    'room': 'Rom',
    'schedule': 'Program',
    'notes': 'Notater',
  };

  static String _titleCase(String raw) {
    final words = raw
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);
    return words
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  /// Formats a metadata value for display. Datetime-looking strings are
  /// rendered with a readable date/time format; lists are comma-joined.
  static String _formatValue(dynamic value) {
    if (value == null) return '';
    if (value is List) {
      return value.map(_formatValue).where((v) => v.isNotEmpty).join(', ');
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return '';
      final parsed = DateTime.tryParse(trimmed);
      if (parsed != null && _looksLikeDateTime(trimmed)) {
        return _formatDateTime(parsed);
      }
      return trimmed;
    }
    return value.toString();
  }

  static final RegExp _dateTimeLike = RegExp(r'^\d{4}-\d{2}-\d{2}');

  static bool _looksLikeDateTime(String value) {
    return _dateTimeLike.hasMatch(value);
  }

  static String _formatDateTime(DateTime dt) {
    final hasTime = dt.hour != 0 || dt.minute != 0 || dt.second != 0;
    if (hasTime) {
      return DateFormat('EEE, MMM dd • HH:mm').format(dt);
    }
    return DateFormat('EEE, MMM dd, yyyy').format(dt);
  }
}
