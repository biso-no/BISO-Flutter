/// The notification topic taxonomy.
///
/// A student chooses among [NotificationTopic] values — News, Events, Jobs,
/// Shop. They never see an Appwrite topic id: the campus half is derived from
/// their profile campus by [appwriteTopicIdsFor].
///
/// Mirrored server-side in BISO-Sites at
/// `packages/shared/utils/notification-topics.ts`. The two must agree; a change
/// here needs the same change there.
library;

/// A topic a student can opt into.
enum NotificationTopic { news, events, jobs, shop }

extension NotificationTopicDetails on NotificationTopic {
  /// The logical id, and the prefix of every Appwrite topic id for it.
  String get id => name;

  String get label => switch (this) {
    NotificationTopic.news => 'News',
    NotificationTopic.events => 'Events',
    NotificationTopic.jobs => 'Jobs',
    NotificationTopic.shop => 'Shop',
  };
}

/// The one topic a student does not choose.
///
/// Every device subscribes to it unconditionally so that a true broadcast has a
/// single topic to target. Without it, "broadcast" would have to fan out across
/// every campus topic, and a student subscribed to several of them might be
/// notified more than once for one message.
const String kGeneralTopicId = 'general';

/// The slug used when a campus is unknown, absent, or is National itself.
const String kNationalSlug = 'national';

const Map<String, String> _campusSlugs = <String, String>{
  '1': 'oslo',
  '2': 'bergen',
  '3': 'trondheim',
  '4': 'stavanger',
  '5': kNationalSlug,
};

/// What a student gets before they have answered the prompt.
const Map<String, bool> kDefaultTopicIntent = <String, bool>{
  'news': true,
  'events': true,
  'jobs': true,
  'shop': true,
};

/// The campus slug for [campusId].
///
/// Falls back to [kNationalSlug] for null, empty, or unrecognised ids. That
/// fallback is load-bearing rather than defensive: a profile campus is
/// optional, so "no campus" is a state real students are in. They get national
/// content instead of nothing at all.
String campusSlugFor(String? campusId) =>
    _campusSlugs[campusId] ?? kNationalSlug;

/// The full set of Appwrite topic ids a device should be subscribed to.
///
/// Each enabled logical topic contributes its campus scope *and* the national
/// scope, so that content published as national reaches every campus. For a
/// student whose campus is National those are the same id, and the set
/// collapses it.
Set<String> appwriteTopicIdsFor({
  required Map<String, bool> intent,
  required String? campusId,
}) {
  final slug = campusSlugFor(campusId);
  final ids = <String>{kGeneralTopicId};
  for (final topic in NotificationTopic.values) {
    if (intent[topic.id] != true) continue;
    ids.add('${topic.id}_$slug');
    ids.add('${topic.id}_$kNationalSlug');
  }
  return ids;
}
