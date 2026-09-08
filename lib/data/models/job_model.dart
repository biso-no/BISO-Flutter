import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../../core/utils/localized_content.dart';
import 'content_translation.dart';

/// Stands in for "no application deadline" while [JobModel.applicationDeadline]
/// is still non-nullable. Far future, never the epoch: an open-ended job must
/// not read as long expired. Task 4 makes the field nullable and removes this.
final _noDeadlineSentinel = DateTime.utc(9999, 12, 31);

class JobModel extends Equatable {
  final String id;
  final String? slug;
  final String title;
  final String description;
  final String? shortDescription;
  final String department;
  final String departmentId;
  final String? departmentLogo;
  final String campusId;
  final List<String> tags;
  final String type; // 'volunteer', 'paid', 'part_time', 'full_time'
  final String
  category; // 'event_help', 'marketing', 'tech', 'administration', etc.
  final List<String> requirements;
  final List<String> responsibilities;
  final List<String> skills; // Required skills
  final String? salary; // For paid positions
  final String? timeCommitment; // e.g., "5 hours/week", "One-time event"
  final DateTime startDate;
  final String url;
  final DateTime? endDate;
  final DateTime applicationDeadline;
  final String applicationMethod; // 'internal', 'external', 'email'
  final String? applicationUrl;
  final String? applicationEmail;
  final String contactPersonName;
  final String? contactPersonEmail;
  final String? contactPersonPhone;
  final int maxApplicants;
  final int currentApplicants;
  final String status; // 'open', 'closed', 'filled', 'cancelled'
  final bool isUrgent;
  final bool isFeatured;
  final List<String> benefits; // What volunteers get
  final Map<String, dynamic> metadata; // Additional job-specific data
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const JobModel({
    required this.id,
    this.slug,
    required this.title,
    required this.description,
    this.shortDescription,
    required this.department,
    required this.departmentId,
    this.departmentLogo,
    required this.campusId,
    this.tags = const [],
    this.type = 'volunteer',
    required this.category,
    this.requirements = const [],
    this.responsibilities = const [],
    this.skills = const [],
    this.salary,
    this.timeCommitment,
    required this.startDate,
    required this.url,
    this.endDate,
    required this.applicationDeadline,
    this.applicationMethod = 'internal',
    this.applicationUrl,
    this.applicationEmail,
    required this.contactPersonName,
    this.contactPersonEmail,
    this.contactPersonPhone,
    this.maxApplicants = 0,
    this.currentApplicants = 0,
    this.status = 'open',
    this.isUrgent = false,
    this.isFeatured = false,
    this.benefits = const [],
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

    // A missing deadline means "open-ended", NOT "expired". This is the
    // opposite of the events case, so the epoch sentinel used there would be
    // exactly wrong here — it would render an open-ended job as long expired.
    // Use a far-future sentinel until Task 4 makes the field nullable.
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
      applicationDeadline: deadline ?? _noDeadlineSentinel,
      metadata: metadata,
      // No Appwrite column; removed in Task 4.
      department: '',
      departmentId: (row['department_id'] ?? '').toString(),
      category: '',
      startDate: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      url: '',
      contactPersonName: '',
      createdAt: parseDate(row[r'$createdAt']),
      updatedAt: parseDate(row[r'$updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'department': department,
      'department_id': departmentId,
      'department_logo': departmentLogo,
      'campus_id': campusId,
      'type': type,
      'category': category,
      'requirements': requirements,
      'responsibilities': responsibilities,
      'skills': skills,
      'salary': salary,
      'time_commitment': timeCommitment,
      'start_date': startDate.toIso8601String(),
      'url': url,
      'end_date': endDate?.toIso8601String(),
      'application_deadline': applicationDeadline.toIso8601String(),
      'application_method': applicationMethod,
      'application_url': applicationUrl,
      'application_email': applicationEmail,
      'contact_person_name': contactPersonName,
      'contact_person_email': contactPersonEmail,
      'contact_person_phone': contactPersonPhone,
      'max_applicants': maxApplicants,
      'current_applicants': currentApplicants,
      'status': status,
      'is_urgent': isUrgent,
      'is_featured': isFeatured,
      'benefits': benefits,
      'metadata': metadata,
    };
  }

  JobModel copyWith({
    String? id,
    String? title,
    String? description,
    String? department,
    String? departmentId,
    String? departmentLogo,
    String? campusId,
    String? type,
    String? category,
    List<String>? requirements,
    List<String>? responsibilities,
    List<String>? skills,
    String? salary,
    String? timeCommitment,
    DateTime? startDate,
    String? url,
    DateTime? endDate,
    DateTime? applicationDeadline,
    String? applicationMethod,
    String? applicationUrl,
    String? applicationEmail,
    String? contactPersonName,
    String? contactPersonEmail,
    String? contactPersonPhone,
    int? maxApplicants,
    int? currentApplicants,
    String? status,
    bool? isUrgent,
    bool? isFeatured,
    List<String>? benefits,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return JobModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      department: department ?? this.department,
      departmentId: departmentId ?? this.departmentId,
      departmentLogo: departmentLogo ?? this.departmentLogo,
      campusId: campusId ?? this.campusId,
      type: type ?? this.type,
      category: category ?? this.category,
      requirements: requirements ?? this.requirements,
      responsibilities: responsibilities ?? this.responsibilities,
      skills: skills ?? this.skills,
      salary: salary ?? this.salary,
      timeCommitment: timeCommitment ?? this.timeCommitment,
      startDate: startDate ?? this.startDate,
      url: url ?? this.url,
      endDate: endDate ?? this.endDate,
      applicationDeadline: applicationDeadline ?? this.applicationDeadline,
      applicationMethod: applicationMethod ?? this.applicationMethod,
      applicationUrl: applicationUrl ?? this.applicationUrl,
      applicationEmail: applicationEmail ?? this.applicationEmail,
      contactPersonName: contactPersonName ?? this.contactPersonName,
      contactPersonEmail: contactPersonEmail ?? this.contactPersonEmail,
      contactPersonPhone: contactPersonPhone ?? this.contactPersonPhone,
      maxApplicants: maxApplicants ?? this.maxApplicants,
      currentApplicants: currentApplicants ?? this.currentApplicants,
      status: status ?? this.status,
      isUrgent: isUrgent ?? this.isUrgent,
      isFeatured: isFeatured ?? this.isFeatured,
      benefits: benefits ?? this.benefits,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isOpen => status == 'open';
  bool get isClosed => status == 'closed';
  bool get isFilled => status == 'filled';
  bool get isCancelled => status == 'cancelled';
  bool get canApply =>
      isOpen &&
      (maxApplicants == 0 || currentApplicants < maxApplicants) &&
      applicationDeadline.isAfter(DateTime.now());
  bool get isPaid =>
      type == 'paid' || type == 'part_time' || type == 'full_time';
  String get displayType {
    switch (type) {
      case 'volunteer':
        return 'Volunteer';
      case 'paid':
        return 'Paid Position';
      case 'part_time':
        return 'Part Time';
      case 'full_time':
        return 'Full Time';
      default:
        return type;
    }
  }

  @override
  List<Object?> get props => [
    id,
    slug,
    title,
    description,
    shortDescription,
    department,
    departmentId,
    departmentLogo,
    campusId,
    tags,
    type,
    category,
    requirements,
    responsibilities,
    skills,
    salary,
    timeCommitment,
    startDate,
    endDate,
    applicationDeadline,
    applicationMethod,
    applicationUrl,
    applicationEmail,
    contactPersonName,
    contactPersonEmail,
    contactPersonPhone,
    maxApplicants,
    currentApplicants,
    status,
    isUrgent,
    isFeatured,
    benefits,
    metadata,
    createdAt,
    updatedAt,
  ];

}
