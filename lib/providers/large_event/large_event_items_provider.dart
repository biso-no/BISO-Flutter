import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../data/models/large_event_model.dart';
import '../../data/services/large_event_item_service.dart';

final largeEventItemServiceProvider = Provider<LargeEventItemService>((ref) {
  return LargeEventItemService();
});

class LargeEventItemsState {
  final List<LargeEventScheduleItem> items;
  final bool isLoading;
  final String? error;

  const LargeEventItemsState({
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  LargeEventItemsState copyWith({
    List<LargeEventScheduleItem>? items,
    bool? isLoading,
    String? error,
  }) {
    return LargeEventItemsState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class LargeEventItemsNotifier extends StateNotifier<LargeEventItemsState> {
  final Ref _ref;
  LargeEventItemsNotifier(this._ref) : super(const LargeEventItemsState());

  Future<void> load({required String eventId, required String campusId}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final items = await _ref
          .read(largeEventItemServiceProvider)
          .listItems(eventId: eventId, campusId: campusId);
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }
}

final largeEventItemsProvider = StateNotifierProvider.autoDispose
    .family<
      LargeEventItemsNotifier,
      LargeEventItemsState,
      ({String eventId, String campusId})
    >((ref, params) {
      final notifier = LargeEventItemsNotifier(ref);
      notifier.load(eventId: params.eventId, campusId: params.campusId);
      return notifier;
    });
