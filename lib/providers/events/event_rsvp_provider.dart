import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/event_rsvp.dart';
import '../../data/services/event_rsvp_api_client.dart';
import '../auth/auth_provider.dart';

/// Injectable seam for tests (offline fakes).
final eventRsvpApiProvider = Provider<EventRsvpApi>(
  (ref) => EventRsvpApiClient(),
);

class EventRsvpState {
  const EventRsvpState({
    this.summary,
    this.loading = false,
    this.saving = false,
  });

  /// Null until loaded, and when loading failed.
  final EventRsvpSummary? summary;
  final bool loading;
  final bool saving;

  EventRsvpState copyWith({
    EventRsvpSummary? summary,
    bool? loading,
    bool? saving,
  }) => EventRsvpState(
    summary: summary ?? this.summary,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
  );
}

class EventRsvpNotifier extends StateNotifier<EventRsvpState> {
  EventRsvpNotifier(this._api, this._eventId, {required bool signedIn})
    : _signedIn = signedIn,
      super(const EventRsvpState()) {
    load();
  }

  final EventRsvpApi _api;
  final String _eventId;
  final bool _signedIn;

  /// Fetches the counts. A failure leaves the summary null, quietly.
  Future<void> load() async {
    state = state.copyWith(loading: true);
    try {
      final summary = await _api.fetch(_eventId, signedIn: _signedIn);
      if (!mounted) return;
      state = state.copyWith(summary: summary, loading: false);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(loading: false);
    }
  }

  /// Shows [status] at once and saves it. Returns false when the save failed
  /// (the previous summary is restored) or when the call was ignored.
  Future<bool> respond(EventRsvpStatus? status) async {
    final previous = state.summary;
    if (state.saving || previous == null) return false;
    state = state.copyWith(summary: previous.withAnswer(status), saving: true);
    try {
      final summary = await _api.respond(_eventId, status);
      if (!mounted) return true;
      state = state.copyWith(summary: summary, saving: false);
      return true;
    } catch (_) {
      if (!mounted) return false;
      state = state.copyWith(summary: previous, saving: false);
      return false;
    }
  }
}

final eventRsvpProvider = StateNotifierProvider.autoDispose
    .family<EventRsvpNotifier, EventRsvpState, String>((ref, eventId) {
      final signedIn =
          ref.watch(authStateProvider.select((s) => s.signedInUserId)) != null;
      return EventRsvpNotifier(
        ref.watch(eventRsvpApiProvider),
        eventId,
        signedIn: signedIn,
      );
    });
