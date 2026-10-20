import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../../core/utils/appwrite_image.dart';
import '../services/deep_link_service.dart';

/// One piece of linked content (event, news article or job) inside a
/// notification, as stored in the `announcements.items` JSON column.
class InboxItem extends Equatable {
  final String type; // event | news | job
  final String id;
  final String? titleEn;
  final String? titleNo;
  final String? image;
  final DateTime? date;
  final String? campusId;

  const InboxItem({
    required this.type,
    required this.id,
    this.titleEn,
    this.titleNo,
    this.image,
    this.date,
    this.campusId,
  });

  static const Set<String> _types = {'event', 'news', 'job'};

  /// The title in [locale] (`no` or anything else for English), falling back
  /// to the other language, then to an empty string.
  String title(String locale) {
    final no = _clean(titleNo);
    final en = _clean(titleEn);
    return (locale == 'no' ? (no ?? en) : (en ?? no)) ?? '';
  }

  /// The in-app route that opens this item.
  String get route => switch (type) {
    'event' => eventRouteFor(id),
    'news' => newsRouteFor(id),
    _ => jobRouteFor(id),
  };

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Parses the `items` JSON array. Returns `[]` for null, empty or invalid
  /// input and skips elements with an unknown `type` or no `id`.
  static List<InboxItem> listFromJson(String? json) {
    if (json == null || json.trim().isEmpty) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      return const [];
    }
    if (decoded is! List) return const [];
    final result = <InboxItem>[];
    for (final element in decoded) {
      if (element is! Map) continue;
      final type = element['type'];
      final id = element['id'];
      if (type is! String || !_types.contains(type)) continue;
      if (id is! String || id.isEmpty) continue;
      final date = element['date'];
      final campus = element['campus_id'];
      result.add(
        InboxItem(
          type: type,
          id: id,
          titleEn: element['title_en'] as String?,
          titleNo: element['title_no'] as String?,
          image: appwriteImageUrl(element['image']),
          date: date is String ? DateTime.tryParse(date) : null,
          campusId: campus is String && campus.isNotEmpty ? campus : null,
        ),
      );
    }
    return result;
  }

  @override
  List<Object?> get props => [
    type,
    id,
    titleEn,
    titleNo,
    image,
    date,
    campusId,
  ];
}
