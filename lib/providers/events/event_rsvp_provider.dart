import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/event_rsvp.dart';
import '../../data/services/event_rsvp_api_client.dart';
import '../auth/auth_provider.dart';

/// Injectable seam for tests (offline fakes).
final eventRsvpApiProvider = Provider<EventRsvpApi>(
  (ref) => EventRsvpApiClient(),
);

/// What became of a call to [EventRsvpNotifier.respond].
enum EventRsvpSaveResult {
  saved,

  /// The server did not take the answer; the previous one is back.
  failed,

  /// Nothing was sent: a save was already running, or nothing is loaded.
  ignored,
}

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

/// Rebuilt when the student signs in or out. Every await below checks that
/// the build it started in is still current, so an answer for the previous
/// one never lands.
class EventRsvpNotifier extends Notifier<EventRsvpState> {
  EventRsvpNotifier(this._eventId);

  final String _eventId;
  late EventRsvpApi _api;
  late bool _signedIn;

  /// The current build, until the provider is invalidated or disposed.
  late _Build _build;

  @override
  EventRsvpState build() {
    final current = _build = _Build();
    ref.onDispose(() => current.live = false);
    _api = ref.watch(eventRsvpApiProvider);
    _signedIn =
        ref.watch(authStateProvider.select((s) => s.signedInUserId)) != null;
    unawaited(_fetch());
    return const EventRsvpState(loading: true);
  }

  /// Fetches the counts. A failure leaves the summary null, quietly.
  Future<void> load() async {
    state = state.copyWith(loading: true);
    await _fetch();
  }

  Future<void> _fetch() async {
    final build = _build;
    try {
      // Future.sync: a call that throws at once must still reach the catch
      // below only after build() has returned, when `state` can be read.
      final summary = await Future.sync(
        () => _api.fetch(_eventId, signedIn: _signedIn),
      );
      if (!build.live) return;
      state = state.copyWith(summary: summary, loading: false);
    } catch (_) {
      if (!build.live) return;
      state = state.copyWith(loading: false);
    }
  }

  /// Fetches the counts again and replaces the summary. Keeps the current
  /// one while loading and when the fetch fails, and does nothing while an
  /// answer is being saved (the save brings the server's summary itself).
  Future<void> refresh() async {
    if (state.saving) return;
    final build = _build;
    try {
      final summary = await _api.fetch(_eventId, signedIn: _signedIn);
      if (!build.live || state.saving) return;
      state = state.copyWith(summary: summary);
    } catch (_) {
      // Keep what is shown.
    }
  }

  /// Shows [status] at once and saves it. A failed save puts the previous
  /// summary back and fetches the server's, so a closed event hides the card.
  Future<EventRsvpSaveResult> respond(EventRsvpStatus? status) async {
    final previous = state.summary;
    if (state.saving || previous == null) return EventRsvpSaveResult.ignored;
    state = state.copyWith(summary: previous.withAnswer(status), saving: true);
    final build = _build;
    try {
      final summary = await _api.respond(_eventId, status);
      if (!build.live) return EventRsvpSaveResult.saved;
      state = state.copyWith(summary: summary, saving: false);
      return EventRsvpSaveResult.saved;
    } catch (_) {
      if (!build.live) return EventRsvpSaveResult.failed;
      state = state.copyWith(summary: previous, saving: false);
      unawaited(refresh());
      return EventRsvpSaveResult.failed;
    }
  }
}

class _Build {
  bool live = true;
}

final eventRsvpProvider = NotifierProvider.autoDispose
    .family<EventRsvpNotifier, EventRsvpState, String>(EventRsvpNotifier.new);
