import '../models/app_notification_model.dart';
import 'deep_link_service.dart';

/// Where an announcement opens, from its push payload or its `announcements`
/// row: the in-app location of its `deep_link`, else its linked content
/// (`content_type` + `content_id`), else its legacy `event_id`, else the
/// announcement itself (`announcement_id`). Null when it carries none of them.
///
/// The one rule for both a push tap and an inbox row, so the two cannot open
/// different places.
String? announcementRouteForData(Map<String, dynamic> data) {
  final deepLink = _text(data['deep_link']);
  final uri = deepLink == null ? null : Uri.tryParse(deepLink);
  final linked = uri == null ? null : routeForDeepLink(uri);
  if (linked != null) return linked;

  final contentId = _text(data['content_id']);
  if (contentId != null) {
    final content = switch (data['content_type']) {
      'event' => eventRouteFor(contentId),
      'news' => newsRouteFor(contentId),
      'job' => jobRouteFor(contentId),
      _ => null,
    };
    if (content != null) return content;
  }

  final eventId = _text(data['event_id']);
  if (eventId != null) return eventRouteFor(eventId);

  final announcementId = _text(data['announcement_id']);
  if (announcementId != null) {
    return '/announcements/${Uri.encodeComponent(announcementId)}';
  }
  return null;
}

/// Where tapping [notification] in the inbox opens (see
/// [announcementRouteForData]).
String? announcementRouteFor(AppNotification notification) =>
    announcementRouteForData({
      'deep_link': notification.deepLink,
      'content_type': notification.contentType,
      'content_id': notification.contentId,
      'event_id': notification.eventId,
      'announcement_id': notification.id,
    });

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
