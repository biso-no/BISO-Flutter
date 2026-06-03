import 'dart:convert';

import 'package:equatable/equatable.dart';

/// A single in-app notification inbox item.
///
/// Built by merging an `announcements` row with an optional
/// `user_notifications` row that tracks the per-user read state.
class AppNotification extends Equatable {
  final String id; // announcement id ($id)
  final String title; // localized title
  final String body; // localized body
  final String category; // general | trip | urgent | event
  final String? eventId;
  final String? deepLink;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final bool read;

  /// The `user_notifications` row `$id` if one exists for the current user.
  /// `null` when the item comes only from the broadcast feed.
  final String? userNotificationId;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.createdAt,
    this.eventId,
    this.deepLink,
    this.data = const {},
    this.read = false,
    this.userNotificationId,
  });

  /// Build an inbox item from an `announcements` document.
  ///
  /// Picks the Norwegian copy when [locale] is `no`, falling back to English.
  factory AppNotification.fromAnnouncement(
    Map<String, dynamic> doc, {
    String locale = 'en',
    bool read = false,
    String? userNotificationId,
  }) {
    final isNorwegian = locale == 'no';

    final titleNo = (doc['title_no'] as String?)?.trim();
    final titleEn = (doc['title_en'] as String?)?.trim();
    final bodyNo = (doc['body_no'] as String?)?.trim();
    final bodyEn = (doc['body_en'] as String?)?.trim();

    final title = (isNorwegian ? (titleNo ?? titleEn) : (titleEn ?? titleNo)) ?? '';
    final body = (isNorwegian ? (bodyNo ?? bodyEn) : (bodyEn ?? bodyNo)) ?? '';

    final rawEventId = doc['event_id'] as String?;
    final eventId = (rawEventId != null && rawEventId.isNotEmpty) ? rawEventId : null;

    final rawDeepLink = doc['deep_link'] as String?;
    final deepLink = (rawDeepLink != null && rawDeepLink.isNotEmpty) ? rawDeepLink : null;

    // sent_at ?? $createdAt (fall back to "now" if both are missing/invalid).
    final createdAt = _parseDate(doc['sent_at']) ?? _parseDate(doc['\$createdAt']) ?? DateTime.now();

    return AppNotification(
      id: (doc['\$id'] as String?) ?? '',
      title: title,
      body: body,
      category: (doc['category'] as String?) ?? 'general',
      eventId: eventId,
      deepLink: deepLink,
      data: _parseData(doc['data']),
      createdAt: createdAt,
      read: read,
      userNotificationId: userNotificationId,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  static Map<String, dynamic> _parseData(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        // Ignore malformed json payloads.
      }
    }
    return const {};
  }

  AppNotification copyWith({
    String? id,
    String? title,
    String? body,
    String? category,
    String? eventId,
    String? deepLink,
    Map<String, dynamic>? data,
    DateTime? createdAt,
    bool? read,
    String? userNotificationId,
  }) {
    return AppNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      category: category ?? this.category,
      eventId: eventId ?? this.eventId,
      deepLink: deepLink ?? this.deepLink,
      data: data ?? this.data,
      createdAt: createdAt ?? this.createdAt,
      read: read ?? this.read,
      userNotificationId: userNotificationId ?? this.userNotificationId,
    );
  }

  @override
  List<Object?> get props => [
    id,
    title,
    body,
    category,
    eventId,
    deepLink,
    data,
    createdAt,
    read,
    userNotificationId,
  ];
}
