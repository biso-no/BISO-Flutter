import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../../core/utils/localized_content.dart';
import 'content_translation.dart';

class JobModel extends Equatable {
  final String id;
  final String? slug;
  final String title;
  final String description;
  final String? shortDescription;
  final String departmentId;
  final String campusId;
  final List<String> tags;
  final String status; // 'draft', 'published', 'closed'
  final DateTime? applicationDeadline;
  final Map<String, dynamic> metadata; // Additional job-specific data
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const JobModel({
    required this.id,
    this.slug,
    required this.title,
    required this.description,
    this.shortDescription,
    required this.departmentId,
    required this.campusId,
    this.tags = const [],
    this.status = 'published',
    this.applicationDeadline,
    this.metadata = const {},
    this.createdAt,
    this.updatedAt,
  });

  factory JobModel.fromAppwriteRow(
    Map<String, dynamic> row, {
    String locale = 'no',
  }) {
    final translations = ContentTranslation.listFrom(row['translations']);
    final content = resolveLocalizedContent(translations, locale);

    Map<String, dynamic> metadata = const {};
    final rawMetadata = row['metadata'];
    if (rawMetadata is String && rawMetadata.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawMetadata);
        if (decoded is Map) metadata = Map<String, dynamic>.from(decoded);
      } catch (_) {
        // Malformed metadata must not sink the whole row.
        metadata = const {};
      }
    }

    final rawTags = metadata['tags'];
    final tags = rawTags is List
        ? rawTags.map((e) => e.toString()).toList(growable: false)
        : const <String>[];

    DateTime? parseDate(Object? v) {
      final s = v?.toString();
      if (s == null || s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    // A missing deadline means "open-ended", not expired.
    final deadline = parseDate(row['application_deadline']);

    return JobModel(
      id: (row[r'$id'] ?? '').toString(),
      slug: row['slug']?.toString(),
      title: content.title,
      description: content.description,
      shortDescription: content.shortDescription,
      campusId: (row['campus_id'] ?? '').toString(),
      tags: tags,
      status: (row['status'] ?? 'published').toString(),
      applicationDeadline: deadline,
      metadata: metadata,
      departmentId: (row['department_id'] ?? '').toString(),
      createdAt: parseDate(row[r'$createdAt']),
      updatedAt: parseDate(row[r'$updatedAt']),
    );
  }

  JobModel copyWith({
    String? id,
    String? slug,
    String? title,
    String? description,
    String? shortDescription,
    String? departmentId,
    String? campusId,
    List<String>? tags,
    String? status,
    DateTime? applicationDeadline,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return JobModel(
      id: id ?? this.id,
      slug: slug ?? this.slug,
      title: title ?? this.title,
      description: description ?? this.description,
      shortDescription: shortDescription ?? this.shortDescription,
      departmentId: departmentId ?? this.departmentId,
      campusId: campusId ?? this.campusId,
      tags: tags ?? this.tags,
      status: status ?? this.status,
      applicationDeadline: applicationDeadline ?? this.applicationDeadline,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // There are deliberately NO status-derived lifecycle getters here.
  //
  // `status` is the editorial enum `draft` / `published` / `closed`, and every
  // read is hard-filtered to `published` (see `JobService._jobFilters`), so any
  // `status ==` flag is a constant for every row the app can fetch. Whether a
  // job is still open is derived from `applicationDeadline` instead — and a
  // null deadline means open-ended, not expired. Do NOT "restore" `isOpen` /
  // `isClosed` / `isFilled` / `isCancelled`; the last two are not even values
  // of the enum.

  @override
  List<Object?> get props => [
    id,
    slug,
    title,
    description,
    shortDescription,
    departmentId,
    campusId,
    tags,
    status,
    applicationDeadline,
    metadata,
    createdAt,
    updatedAt,
  ];
}
