import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../data/models/entur_models.dart';
import '../../data/services/entur_service.dart';
import '../campus/campus_provider.dart';

final enturServiceProvider = Provider<EnturService>((ref) {
  final service = EnturService();
  ref.onDispose(service.dispose);
  return service;
});

final stopPlacesForCampusProvider = FutureProvider<List<StopPlaceModel>>((ref) async {
  final campus = ref.watch(filterCampusProvider);
  final entur = ref.watch(enturServiceProvider);
  try {
    return await entur.getStopPlacesForCampus(campus.id);
  } catch (e, stackTrace) {
    AppLogger.error(
      'Failed to load stop places',
      error: e,
      stackTrace: stackTrace,
      extra: {'campus_id': campus.id},
    );
    rethrow;
  }
});

class EnturUiState {
  final bool showBus;
  final bool showMetro;
  final String? selectedStopPlaceId;
  final EnturDepartureBoard? board;

  EnturUiState({
    required this.showBus,
    required this.showMetro,
    this.selectedStopPlaceId,
    this.board,
  });

  EnturUiState copyWith({
    bool? showBus,
    bool? showMetro,
    String? selectedStopPlaceId,
    EnturDepartureBoard? board,
  }) {
    return EnturUiState(
      showBus: showBus ?? this.showBus,
      showMetro: showMetro ?? this.showMetro,
      selectedStopPlaceId: selectedStopPlaceId ?? this.selectedStopPlaceId,
      board: board ?? this.board,
    );
  }
}

final enturUiProvider = NotifierProvider<EnturUiNotifier, EnturUiState>(
  EnturUiNotifier.new,
);

class EnturUiNotifier extends Notifier<EnturUiState> {
  late EnturService _service;

  @override
  EnturUiState build() {
    _service = ref.watch(enturServiceProvider);
    return EnturUiState(showBus: true, showMetro: true);
  }

  void setStopPlace(String? stopPlaceId) async {
    state = state.copyWith(selectedStopPlaceId: stopPlaceId);
    if (stopPlaceId == null) return;
    final board = await _service.getDeparturesByStopPlaceId(stopPlaceId);
    state = state.copyWith(board: board);
    _service.subscribeToDepartures(stopPlaceId);
    _service.boardStream.listen((b) {
      state = state.copyWith(board: b);
    });
  }

  void toggleBus() => state = state.copyWith(showBus: !state.showBus);
  void toggleMetro() => state = state.copyWith(showMetro: !state.showMetro);
}



