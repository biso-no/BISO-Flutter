/// The notification topic taxonomy.
///
/// A student chooses among [NotificationTopic] values — News, Events, Jobs,
/// Shop. They never see an Appwrite topic id: the campus half is derived from
/// their profile campus by [appwriteTopicIdsFor].
///
/// Every Appwrite topic id ends in a language suffix (`_no` or `_en`). A phone
/// subscribes to exactly one language, so the server can send each message in
/// the language the reader chose. Ids look like `general_{lang}`,
/// `general_{campus}_{lang}` and `{topic}_{campus|national}_{lang}`.
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

/// The languages a push topic can carry. A device subscribes to exactly one.
const List<String> kPushLocales = <String>['no', 'en'];

/// The push language for a UI language code.
///
/// Norwegian variants (`nb`, `nn`, `no`, any case) give `'no'`; everything else
/// gives `'en'`.
String pushLocaleFor(String languageCode) =>
    switch (languageCode.toLowerCase()) {
      'nb' || 'nn' || 'no' => 'no',
      _ => 'en',
    };

/// The full set of Appwrite topic ids a device should be subscribed to.
///
/// Always `general_{locale}`, plus `general_{campus}_{locale}` unless the
/// campus is National (there is no `general_national_*`). Each enabled logical
/// topic contributes its campus scope *and* the national scope, so that
/// content published as national reaches every campus. For a student whose
/// campus is National those are the same id, and the set collapses it.
Set<String> appwriteTopicIdsFor({
  required Map<String, bool> intent,
  required String? campusId,
  required String locale,
}) {
  final slug = campusSlugFor(campusId);
  final ids = <String>{'${kGeneralTopicId}_$locale'};
  if (slug != kNationalSlug) ids.add('${kGeneralTopicId}_${slug}_$locale');
  for (final topic in NotificationTopic.values) {
    if (intent[topic.id] != true) continue;
    ids.add('${topic.id}_${slug}_$locale');
    ids.add('${topic.id}_${kNationalSlug}_$locale');
  }
  return ids;
}

/// Every topic id a device can ever hold, across all campuses and languages.
List<String> allPushTopicIds() {
  final campusSlugs = _campusSlugs.values.toSet();
  final ids = <String>[];
  for (final locale in kPushLocales) {
    ids.add('${kGeneralTopicId}_$locale');
    for (final slug in campusSlugs) {
      if (slug != kNationalSlug) ids.add('${kGeneralTopicId}_${slug}_$locale');
    }
    for (final topic in NotificationTopic.values) {
      for (final slug in campusSlugs) {
        ids.add('${topic.id}_${slug}_$locale');
      }
    }
  }
  return ids;
}
