import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class LargeEventItemsNotifier extends Notifier<LargeEventItemsState> {
  LargeEventItemsNotifier(this._params);

  final ({String eventId, String campusId}) _params;

  @override
  LargeEventItemsState build() {
    unawaited(_load());
    return const LargeEventItemsState(isLoading: true);
  }

  Future<void> _load() async {
    // The screen can close before the items arrive.
    final ref = this.ref;
    try {
      // Future.sync: a call that throws at once must still reach the catch
      // below only after build() has returned, when `state` can be read.
      final items = await Future.sync(
        () => ref.read(largeEventItemServiceProvider).listItems(
          eventId: _params.eventId,
          campusId: _params.campusId,
        ),
      );
      if (!ref.mounted) return;
      state = state.copyWith(items: items, isLoading: false);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }
}

final largeEventItemsProvider = NotifierProvider.autoDispose
    .family<
      LargeEventItemsNotifier,
      LargeEventItemsState,
      ({String eventId, String campusId})
    >(LargeEventItemsNotifier.new);
