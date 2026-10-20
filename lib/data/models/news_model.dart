import 'package:equatable/equatable.dart';

import '../../core/utils/appwrite_image.dart';
import '../../core/utils/localized_content.dart';
import 'content_translation.dart';

class NewsModel extends Equatable {
  final String id;
  final String? slug;
  final String title;

  /// HTML from the admin editor, or '' when there is none.
  final String body;
  final String? shortDescription;
  final String? image;
  final String campusId;
  final String? author;

  /// The row's `$createdAt`, which is the publish timestamp the web sorts by.
  final DateTime publishedAt;
  final bool sticky;

  const NewsModel({
    required this.id,
    this.slug,
    required this.title,
    required this.body,
    this.shortDescription,
    this.image,
    required this.campusId,
    this.author,
    required this.publishedAt,
    this.sticky = false,
  });

  factory NewsModel.fromAppwriteRow(
    Map<String, dynamic> row, {
    String locale = 'no',
  }) {
    final translations = ContentTranslation.listFrom(row['translation_refs']);
    final content = resolveLocalizedContent(translations, locale);
    final created = DateTime.tryParse((row[r'$createdAt'] ?? '').toString());

    return NewsModel(
      id: (row[r'$id'] ?? '').toString(),
      slug: row['slug']?.toString(),
      title: content.title,
      body: content.description,
      shortDescription: content.shortDescription,
      image: appwriteImageUrl(row['image']),
      campusId: (row['campus_id'] ?? '').toString(),
      author: row['author']?.toString(),
      publishedAt: created ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      sticky: row['sticky'] == true,
    );
  }

  /// False for an empty body and for older rows stored as Plate JSON, which
  /// the app cannot render as HTML.
  bool get hasRenderableBody {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return false;
    return !trimmed.startsWith('[') && !trimmed.startsWith('{');
  }

  @override
  List<Object?> get props => [
    id,
    slug,
    title,
    body,
    shortDescription,
    image,
    campusId,
    author,
    publishedAt,
    sticky,
  ];
}
