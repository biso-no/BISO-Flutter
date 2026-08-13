import 'package:equatable/equatable.dart';

/// A news article published through the BISO Sites CMS.
class NewsModel extends Equatable {
  final String id;
  final String title;
  final String content; // HTML body
  final String? shortDescription;
  final String campusId;
  final String? campusName;
  final String? departmentId;
  final String? departmentName;
  final bool sticky;
  final String? image;
  final String? author;
  final String url; // Canonical article URL on biso.no
  final String? externalUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const NewsModel({
    required this.id,
    required this.title,
    required this.content,
    this.shortDescription,
    required this.campusId,
    this.campusName,
    this.departmentId,
    this.departmentName,
    this.sticky = false,
    this.image,
    this.author,
    this.url = '',
    this.externalUrl,
    this.createdAt,
    this.updatedAt,
  });

  factory NewsModel.fromBisoApi(Map<String, dynamic> map) {
    return NewsModel(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      content: (map['content'] ?? '').toString(),
      shortDescription: map['short_description']?.toString(),
      campusId: (map['campus_id'] ?? '').toString(),
      campusName: map['campus_name']?.toString(),
      departmentId: map['department_id']?.toString(),
      departmentName: map['department_name']?.toString(),
      sticky: map['sticky'] == true,
      image: map['image']?.toString(),
      author: map['author']?.toString(),
      url: (map['url'] ?? '').toString(),
      externalUrl: map['external_url']?.toString(),
      createdAt: DateTime.tryParse((map['created_at'] ?? '').toString()),
      updatedAt: DateTime.tryParse((map['updated_at'] ?? '').toString()),
    );
  }

  @override
  List<Object?> get props => [
    id,
    title,
    content,
    shortDescription,
    campusId,
    campusName,
    departmentId,
    departmentName,
    sticky,
    image,
    author,
    url,
    externalUrl,
    createdAt,
    updatedAt,
  ];
}
