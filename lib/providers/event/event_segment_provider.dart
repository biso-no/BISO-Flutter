import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/event_segment_model.dart';
import '../../data/services/event_segment_service.dart';
import '../auth/auth_provider.dart';

final eventSegmentServiceProvider = Provider<EventSegmentService>(
  (ref) => EventSegmentService(),
);

/// The signed-in user's assigned segment(s) ("Your trip") for a given event id.
///
/// Returns an empty list when signed out, consistent with the app's
/// public-first / conditional-auth model.
final myTripProvider = FutureProvider.family<List<EventSegment>, String>((
  ref,
  eventId,
) async {
  final userId = ref.watch(authStateProvider).user?.id;
  if (userId == null || userId.isEmpty) {
    return const <EventSegment>[];
  }

  final service = ref.watch(eventSegmentServiceProvider);
  return service.fetchMyTrip(eventId: eventId, userId: userId);
});
