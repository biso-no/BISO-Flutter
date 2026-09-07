import 'package:equatable/equatable.dart';

/// A single localized row from the `content_translations` table.
class ContentTranslation extends Equatable {
  final String locale;
  final String title;
  final String description;
  final String? shortDescription;
  final String? additionalFields;
  final String contentType;
  final String contentId;

  const ContentTranslation({
    required this.locale,
    required this.title,
    required this.description,
    this.shortDescription,
    this.additionalFields,
    this.contentType = '',
    this.contentId = '',
  });

  factory ContentTranslation.fromMap(Map<String, dynamic> map) {
    return ContentTranslation(
      locale: (map['locale'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      shortDescription: map['short_description']?.toString(),
      additionalFields: map['additional_fields']?.toString(),
      contentType: (map['content_type'] ?? '').toString(),
      contentId: (map['content_id'] ?? '').toString(),
    );
  }

  /// Parses a nested relationship array such as `translation_refs`.
  static List<ContentTranslation> listFrom(Object? value) {
    if (value is! List) return const <ContentTranslation>[];
    return value
        .whereType<Map>()
        .map((e) => ContentTranslation.fromMap(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  @override
  List<Object?> get props => [
    locale,
    title,
    description,
    shortDescription,
    additionalFields,
    contentType,
    contentId,
  ];
}
