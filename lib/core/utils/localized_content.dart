import '../../data/models/content_translation.dart';

/// Title and description resolved for one locale.
class LocalizedContent {
  final String title;
  final String description;
  final String? shortDescription;

  const LocalizedContent({
    required this.title,
    required this.description,
    this.shortDescription,
  });

  static const empty = LocalizedContent(title: '', description: '');
}

/// Picks the best translation for [locale].
///
/// Locale selection is deliberately client-side. Filtering by
/// `translation_refs.locale` in Appwrite narrows parent rows rather than the
/// nested array, which would silently hide content lacking that locale.
///
/// Fallback order: requested -> 'no' -> 'en' -> first available -> empty.
///
/// Locale preference only applies among translations that actually have a
/// usable (non-blank, non-whitespace) title. A partially-synced translation
/// row can carry a real locale but an empty title; picking that row purely
/// because its locale matches would surface a blank title even though
/// another translation has real content. So the fallback chain first runs
/// over translations with a usable title, and only falls back to
/// considering blank-title rows (yielding blank content, as today) when none
/// of the translations have any usable title at all. This guarantees the
/// resolver never yields a blank title when any translation in the list has
/// one.
LocalizedContent resolveLocalizedContent(
  List<ContentTranslation> translations,
  String locale,
) {
  if (translations.isEmpty) return LocalizedContent.empty;

  ContentTranslation? pick(List<ContentTranslation> candidates, String wanted) {
    for (final t in candidates) {
      if (t.locale == wanted) return t;
    }
    return null;
  }

  ContentTranslation resolveFrom(List<ContentTranslation> candidates) {
    return pick(candidates, locale) ??
        pick(candidates, 'no') ??
        pick(candidates, 'en') ??
        candidates.first;
  }

  final withTitle = translations
      .where((t) => t.title.trim().isNotEmpty)
      .toList(growable: false);

  final chosen = resolveFrom(withTitle.isNotEmpty ? withTitle : translations);

  return LocalizedContent(
    title: chosen.title,
    description: chosen.description,
    shortDescription: chosen.shortDescription,
  );
}
