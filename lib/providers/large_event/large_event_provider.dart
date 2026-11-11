import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../data/models/large_event_model.dart';
import '../../data/services/large_event_service.dart';
import '../campus/campus_provider.dart';

final largeEventServiceProvider = Provider<LargeEventService>((ref) {
  return LargeEventService();
});

class LargeEventState {
  final List<LargeEventModel> activeEvents;
  final bool isLoading;
  final String? error;

  const LargeEventState({
    this.activeEvents = const [],
    this.isLoading = false,
    this.error,
  });

  LargeEventState copyWith({
    List<LargeEventModel>? activeEvents,
    bool? isLoading,
    String? error,
  }) {
    return LargeEventState(
      activeEvents: activeEvents ?? this.activeEvents,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

final largeEventProvider =
    StateNotifierProvider<LargeEventNotifier, LargeEventState>((ref) {
      return LargeEventNotifier(ref);
    });

class LargeEventNotifier extends StateNotifier<LargeEventState> {
  final Ref _ref;

  LargeEventNotifier(this._ref) : super(const LargeEventState()) {
    loadActive();
    // Live updates
    _ref.read(largeEventServiceProvider).subscribeActiveEvents().listen((_) {
      loadActive();
    });
  }

  Future<void> loadActive() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final events = await _ref
          .read(largeEventServiceProvider)
          .fetchActiveEvents();
      state = state.copyWith(activeEvents: events, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  LargeEventModel? featuredForCampus(String campusId) {
    final now = DateTime.now();
    final eligible = state.activeEvents
        .where((e) => e.isActiveForCampus(campusId, now))
        .where(
          (e) =>
              e.heroOverrideEnabled &&
              (e.campusConfig(campusId)?.heroOverrideEnabled ?? true),
        )
        .toList();
    if (eligible.isEmpty) return null;
    eligible.sort((a, b) => b.priority.compareTo(a.priority));
    return eligible.first;
  }
}

// Convenience provider to get the featured event for current filter campus
final featuredLargeEventProvider = Provider<LargeEventModel?>((ref) {
  final campus = ref.watch(filterCampusProvider);
  final state = ref.watch(largeEventProvider);
  final now = DateTime.now();
  final eligible = state.activeEvents
      .where((e) => e.isActiveForCampus(campus.id, now))
      .where(
        (e) =>
            e.heroOverrideEnabled &&
            (e.campusConfig(campus.id)?.heroOverrideEnabled ?? true),
      )
      .toList();
  if (eligible.isEmpty) return null;
  eligible.sort((a, b) => b.priority.compareTo(a.priority));
  return eligible.first;
});

// Provider to get all showcase items for hero carousel (including different types)
final heroShowcaseItemsProvider = Provider<List<LargeEventModel>>((ref) {
  final campus = ref.watch(filterCampusProvider);
  final state = ref.watch(largeEventProvider);
  final now = DateTime.now();
  
  final eligible = state.activeEvents
      .where((e) => e.isActiveForCampus(campus.id, now))
      .where(
        (e) =>
            e.heroOverrideEnabled &&
            (e.campusConfig(campus.id)?.heroOverrideEnabled ?? true),
      )
      .toList();
  
  // Sort by priority (highest first)
  eligible.sort((a, b) => b.priority.compareTo(a.priority));
  return eligible;
});
