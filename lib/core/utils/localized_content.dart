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
LocalizedContent resolveLocalizedContent(
  List<ContentTranslation> translations,
  String locale,
) {
  if (translations.isEmpty) return LocalizedContent.empty;

  ContentTranslation? pick(String wanted) {
    for (final t in translations) {
      if (t.locale == wanted) return t;
    }
    return null;
  }

  final chosen =
      pick(locale) ?? pick('no') ?? pick('en') ?? translations.first;

  return LocalizedContent(
    title: chosen.title,
    description: chosen.description,
    shortDescription: chosen.shortDescription,
  );
}
