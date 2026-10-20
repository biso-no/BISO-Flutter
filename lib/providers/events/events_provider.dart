import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/event_model.dart';
import '../../data/services/event_service.dart';
import '../ui/locale_provider.dart';

/// Injectable seam for tests (offline fakes).
final eventServiceProvider = Provider<EventService>((ref) => EventService());

/// One published event by slug or row id, in the app's language; null when
/// it does not exist. An event that has ended still opens.
final eventDetailProvider = FutureProvider.autoDispose
    .family<EventModel?, String>((ref, idOrSlug) {
      final locale = ref.watch(localeProvider).languageCode;
      return ref.watch(eventServiceProvider).getEvent(idOrSlug, locale: locale);
    });
