import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../../core/utils/localized_content.dart';
import 'content_translation.dart';

/// The answer types a vacancy's custom questions can have, as the web's
/// `recruitmentCustomQuestionTypeSchema` names them.
enum JobQuestionType {
  text('text'),
  longText('long_text'),
  select('select'),
  multiSelect('multi_select'),
  boolean('boolean'),
  number('number');

  const JobQuestionType(this.wireName);

  /// The name the server stores and expects back as `answer_type.<id>`.
  final String wireName;

  static JobQuestionType? fromWireName(Object? value) {
    for (final type in values) {
      if (type.wireName == value) return type;
    }
    return null;
  }
}

/// One of the questions the hiring team added to a vacancy.
class JobQuestion extends Equatable {
  const JobQuestion({
    required this.id,
    required this.label,
    required this.type,
    this.required = false,
    this.options = const [],
    this.helpText,
  });

  final String id;
  final String label;
  final JobQuestionType type;
  final bool required;

  /// The choices for [JobQuestionType.select] and
  /// [JobQuestionType.multiSelect].
  final List<String> options;
  final String? helpText;

  /// The `custom_questions` column, read the way the server's
  /// `parseRecruitmentCustomQuestions` reads it: all or nothing. One malformed
  /// entry makes the server enforce no questions at all, so the app must not
  /// ask any either.
  static List<JobQuestion> listFrom(Object? value) {
    Object? raw = value;
    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        return const [];
      }
    }
    if (raw is! List || raw.length > _maxQuestions) return const [];
    final questions = <JobQuestion>[];
    for (final entry in raw) {
      final question = entry is Map ? _parse(entry) : null;
      if (question == null) return const [];
      questions.add(question);
    }
    return List.unmodifiable(questions);
  }

  static const _maxQuestions = 20;
  static const _maxOptions = 20;

  static JobQuestion? _parse(Map<dynamic, dynamic> map) {
    final id = _boundedString(map['id'], 50);
    final label = _boundedString(map['label'], 500);
    final type = JobQuestionType.fromWireName(map['type']);
    // Zod's `.default()` fills in a missing key only; an explicit null fails.
    final required = map.containsKey('required') ? map['required'] : false;
    final rawOptions = map.containsKey('options')
        ? map['options']
        : const <Object?>[];
    final helpText = map['help_text'];
    if (id == null || label == null || type == null) return null;
    if (required is! bool || rawOptions is! List) return null;
    if (rawOptions.length > _maxOptions) return null;
    if (helpText != null && helpText is! String) return null;
    final options = <String>[];
    for (final option in rawOptions) {
      final parsed = _boundedString(option, 200);
      if (parsed == null) return null;
      options.add(parsed);
    }
    final help = (helpText as String?)?.trim();
    return JobQuestion(
      id: id,
      label: label,
      type: type,
      required: required,
      options: List.unmodifiable(options),
      helpText: help == null || help.isEmpty ? null : help,
    );
  }

  /// [value] trimmed, when it is a string of 1 to [max] characters.
  static String? _boundedString(Object? value, int max) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty || trimmed.length > max ? null : trimmed;
  }

  @override
  List<Object?> get props => [id, label, type, required, options, helpText];
}

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

  /// The hiring team's questions, asked in the application's Questions step.
  final List<JobQuestion> customQuestions;

  /// The unit's accounting name (`departments.Name`), campus code included.
  final String? departmentName;
  final String? campusName;

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
    this.customQuestions = const [],
    this.departmentName,
    this.campusName,
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

    final translatedSummary = content.shortDescription?.trim() ?? '';

    return JobModel(
      id: (row[r'$id'] ?? '').toString(),
      slug: row['slug']?.toString(),
      title: content.title,
      description: content.description,
      // As on the web: a translation's own summary first, then the one
      // stored on the vacancy.
      shortDescription: translatedSummary.isNotEmpty
          ? content.shortDescription
          : _text(metadata['short_description']),
      campusId: (row['campus_id'] ?? '').toString(),
      tags: tags,
      status: (row['status'] ?? 'published').toString(),
      applicationDeadline: deadline,
      metadata: metadata,
      departmentId: (row['department_id'] ?? '').toString(),
      createdAt: parseDate(row[r'$createdAt']),
      updatedAt: parseDate(row[r'$updatedAt']),
      customQuestions: JobQuestion.listFrom(row['custom_questions']),
      departmentName: _nestedText(row['department'], 'Name'),
      campusName: _nestedText(row['campus'], 'name'),
    );
  }

  /// [value] trimmed, or null when it is not a non-blank string.
  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _nestedText(Object? relation, String key) =>
      relation is Map ? _text(relation[key]) : null;

  // Vacancy details kept in the `metadata` JSON column. Blank means unset.

  /// Only BISO members may apply (`metadata.audience == "members"`); anyone
  /// may still read the vacancy.
  bool get membersOnly => metadata['audience'] == 'members';
  bool get cvRequired => metadata['cv_required'] == true;
  bool get paid => metadata['paid'] == true;
  String? get employmentType => _text(metadata['employment_type']);
  String? get company => _text(metadata['company']);
  String? get location => _text(metadata['location']);
  String? get contactName => _text(metadata['contact_name']);
  String? get contactEmail => _text(metadata['contact_email']);
  String? get commitment => _text(metadata['commitment']);
  String? get term => _text(metadata['term']);

  /// A calendar date such as `2026-11-01`.
  DateTime? get startDate {
    final value = _text(metadata['start_date']);
    return value == null ? null : DateTime.tryParse(value);
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
    List<JobQuestion>? customQuestions,
    String? departmentName,
    String? campusName,
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
      customQuestions: customQuestions ?? this.customQuestions,
      departmentName: departmentName ?? this.departmentName,
      campusName: campusName ?? this.campusName,
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
    customQuestions,
    departmentName,
    campusName,
  ];
}
