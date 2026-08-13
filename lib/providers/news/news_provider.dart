import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/news_model.dart';
import '../../data/services/news_service.dart';

final newsServiceProvider = Provider<NewsService>((ref) => NewsService());

final newsSearchTermProvider = StateProvider<String?>((ref) => null);

/// News feed for a campus (null campusId = all campuses).
final newsProvider = FutureProvider.family<List<NewsModel>, String?>((
  ref,
  campusId,
) {
  final service = ref.watch(newsServiceProvider);
  final searchTerm = ref.watch(newsSearchTermProvider);
  return service.getNews(campusId: campusId, limit: 50, search: searchTerm);
});

/// Resolves a single article by id (deep-link path).
final newsItemProvider = FutureProvider.family<NewsModel?, String>((ref, id) {
  return ref.watch(newsServiceProvider).getNewsItem(id);
});

/// Small latest-news feed for home surfaces.
final latestNewsProvider = FutureProvider.family<List<NewsModel>, String>((
  ref,
  campusId,
) {
  final service = ref.watch(newsServiceProvider);
  return service.getNews(campusId: campusId, limit: 6);
});
