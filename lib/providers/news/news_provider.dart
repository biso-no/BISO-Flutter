import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/news_model.dart';
import '../../data/services/news_service.dart';
import '../ui/locale_provider.dart';

const _latestNewsLimit = 6;

/// Injectable seam for tests (offline fakes).
final newsServiceProvider = Provider<NewsService>((ref) => NewsService());

/// The newest published news for a campus (National included), in the app's
/// language.
final latestNewsProvider = FutureProvider.autoDispose
    .family<List<NewsModel>, String>((ref, campusId) {
      final locale = ref.watch(localeProvider).languageCode;
      return ref
          .watch(newsServiceProvider)
          .listNews(
            campusId: campusId,
            locale: locale,
            limit: _latestNewsLimit,
          );
    });

/// One published article by slug or row id; null when it does not exist.
final newsDetailProvider = FutureProvider.autoDispose
    .family<NewsModel?, String>((ref, idOrSlug) {
      final locale = ref.watch(localeProvider).languageCode;
      return ref.watch(newsServiceProvider).getNews(idOrSlug, locale: locale);
    });
