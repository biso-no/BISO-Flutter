import '../../core/constants/notification_topics.dart';

/// What a device must create and delete to match the student's intent.
class TopicDiff {
  const TopicDiff({required this.toCreate, required this.toDelete});

  /// Appwrite topic ids that need a new subscriber.
  final Set<String> toCreate;

  /// Appwrite topic ids whose subscriber should be deleted.
  final Set<String> toDelete;

  bool get isEmpty => toCreate.isEmpty && toDelete.isEmpty;
}

/// Diff the topics a device *should* hold against the ones it *does*.
///
/// This is what makes reconciliation idempotent: it compares observed state
/// rather than replaying a sequence of toggles, so running it twice is a no-op
/// and two devices never interfere with each other.
TopicDiff computeTopicDiff({
  required Set<String> desired,
  required Map<String, String> current,
}) {
  final held = current.keys.toSet();
  return TopicDiff(
    toCreate: desired.difference(held),
    toDelete: held.difference(desired),
  );
}

/// Old topic id -> new logical id. Anything absent from this map is dropped.
const Map<String, String> _legacyRenames = <String, String>{
  'news': 'news',
  'events': 'events',
  'jobs': 'jobs',
  'products': 'shop',
  // 'expenses' and 'orders' are deliberately absent: both become personal
  // notifications rather than topics.
};

/// Convert a pre-existing `topic_subscriptions` map into the new intent shape.
///
/// Starts from the defaults so a topic with no old equivalent — `news` — is
/// switched on rather than silently missing, then applies whatever the student
/// had actually chosen on top.
Map<String, bool> migrateLegacyIntent(Map<String, bool>? legacy) {
  final intent = Map<String, bool>.from(kDefaultTopicIntent);
  if (legacy == null) return intent;
  for (final entry in legacy.entries) {
    final renamed = _legacyRenames[entry.key];
    if (renamed == null) continue;
    intent[renamed] = entry.value;
  }
  return intent;
}
