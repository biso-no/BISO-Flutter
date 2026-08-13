import 'package:equatable/equatable.dart';

/// A custom application-form question configured on a BISO Sites vacancy.
class JobQuestionModel extends Equatable {
  final String id;
  final String label;
  final String type; // 'text', 'long_text', 'select', 'multi_select', 'boolean', 'number'
  final bool required;
  final String? helpText;
  final List<String> options;

  const JobQuestionModel({
    required this.id,
    required this.label,
    this.type = 'text',
    this.required = false,
    this.helpText,
    this.options = const [],
  });

  factory JobQuestionModel.fromMap(Map<String, dynamic> map) {
    return JobQuestionModel(
      id: (map['id'] ?? '').toString(),
      label: (map['label'] ?? '').toString(),
      type: (map['type'] ?? 'text').toString(),
      required: map['required'] == true,
      helpText: map['help_text']?.toString(),
      options: (map['options'] is List)
          ? (map['options'] as List).map((o) => o.toString()).toList()
          : const [],
    );
  }

  @override
  List<Object?> get props => [id, label, type, required, helpText, options];
}

class JobModel extends Equatable {
  final String id;
  final String title;
  final String description;
  final String department;
  final String departmentId;
  final String? departmentLogo;
  final String campusId;
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
  final String slug;
  final String? shortDescription;
  final bool cvRequired;
  final List<JobQuestionModel> customQuestions;

  const JobModel({
    required this.id,
    required this.title,
    required this.description,
    required this.department,
    required this.departmentId,
    this.departmentLogo,
    required this.campusId,
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
    this.slug = '',
    this.shortDescription,
    this.cvRequired = false,
    this.customQuestions = const [],
  });

  // Create from the BISO Sites API payload (Appwrite-native content)
  factory JobModel.fromBisoApi(Map<String, dynamic> map) {
    final deadline = DateTime.tryParse(
      (map['application_deadline'] ?? '').toString(),
    );
    final createdAt = DateTime.tryParse((map['created_at'] ?? '').toString());
    final isOpen = map['is_open'] != false;
    final paid = map['paid'] == true;
    final tags = (map['tags'] is List)
        ? (map['tags'] as List).map((tag) => tag.toString()).toList()
        : const <String>[];
    final department = (map['department_name'] ?? '').toString().isNotEmpty
        ? map['department_name'].toString()
        : 'BISO';

    return JobModel(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      department: department,
      departmentId: (map['department_id'] ?? '').toString(),
      departmentLogo: null,
      campusId: (map['campus_id'] ?? '').toString(),
      type: paid ? 'paid' : 'volunteer',
      category: (map['employment_type'] ?? '').toString().isNotEmpty
          ? map['employment_type'].toString()
          : 'general',
      requirements: const [],
      responsibilities: const [],
      skills: tags,
      salary: null,
      timeCommitment: map['commitment']?.toString(),
      startDate:
          DateTime.tryParse((map['start_date'] ?? '').toString()) ??
          createdAt ??
          DateTime.now(),
      url: (map['url'] ?? '').toString(),
      endDate: null,
      // No deadline means the vacancy stays open until filled; keep the
      // existing non-null contract with a one-year horizon.
      applicationDeadline:
          deadline ?? DateTime.now().add(const Duration(days: 365)),
      applicationMethod: 'internal',
      applicationUrl: map['url']?.toString(),
      applicationEmail: map['contact_email']?.toString(),
      contactPersonName: (map['contact_name'] ?? '').toString().isNotEmpty
          ? map['contact_name'].toString()
          : department,
      contactPersonEmail: map['contact_email']?.toString(),
      contactPersonPhone: null,
      maxApplicants: 0,
      currentApplicants: 0,
      status: isOpen ? 'open' : 'closed',
      isUrgent: false,
      isFeatured: false,
      benefits: const [],
      metadata: <String, dynamic>{
        'company': map['company'],
        'term': map['term'],
        'location': map['location'],
        'paid': paid,
        'locale': map['locale'],
        'sourceShape': 'biso',
      },
      createdAt: createdAt,
      updatedAt: DateTime.tryParse((map['updated_at'] ?? '').toString()),
      slug: (map['slug'] ?? '').toString(),
      shortDescription: map['short_description']?.toString(),
      cvRequired: map['cv_required'] == true,
      customQuestions: (map['custom_questions'] is List)
          ? (map['custom_questions'] as List)
                .whereType<Map<String, dynamic>>()
                .map(JobQuestionModel.fromMap)
                .toList()
          : const [],
    );
  }

  // Create from the Appwrite Function jobs payload (WordPress-backed)
  factory JobModel.fromFunctionJob(
    Map<String, dynamic> map, {
    required String campusId,
  }) {
    // The jobs endpoint can return either the transformed function payload or
    // raw WordPress REST objects. Keep this parser tolerant of both shapes.
    final classList = _stringList(map['class_list']);
    final isRawWordPressJob =
        map['title'] is Map<String, dynamic> ||
        map['content'] is Map<String, dynamic> ||
        classList.isNotEmpty;
    final typeList = isRawWordPressJob
        ? _taxonomyLabels(classList, 'verv-')
        : _stringList(map['type']);
    final interestsList = isRawWordPressJob
        ? _taxonomyLabels(classList, 'interesser-')
        : _stringList(map['interests']);
    final campusList = isRawWordPressJob
        ? _taxonomyLabels(classList, 'campus-')
        : _stringList(map['campus']);
    final campusSlugs = _taxonomySlugs(classList, 'campus-');
    final title = _decodeHtmlEntities(_renderedString(map['title']));
    final description = _renderedString(map['description']).isNotEmpty
        ? _decodeHtmlEntities(_renderedString(map['description']))
        : _decodeHtmlEntities(_renderedString(map['content']));
    final url = (map['url'] ?? map['link'] ?? '').toString();
    final startDate =
        DateTime.tryParse((map['date'] ?? map['date_gmt'] ?? '').toString()) ??
        DateTime.now();
    final applicationDeadline =
        DateTime.tryParse((map['expiry_date'] ?? '').toString()) ??
        _extractNorwegianDeadline(description) ??
        DateTime.now().add(const Duration(days: 14));
    final resolvedCampusId = _campusIdFromValues(campusList) ?? campusId;

    // Extract department from type array or use first item
    final department = typeList.isNotEmpty
        ? _decodeHtmlEntities(typeList.first.toString())
        : 'BISO';

    return JobModel(
      id: (map['id'] ?? '').toString(),
      title: title,
      description: description,
      department: department,
      departmentId: '',
      departmentLogo: null,
      campusId: resolvedCampusId,
      type: 'volunteer',
      category: typeList.isNotEmpty
          ? _decodeHtmlEntities(typeList.first.toString())
          : 'general',
      requirements: List<String>.from(
        interestsList.map((e) => _decodeHtmlEntities(e.toString())),
      ),
      responsibilities: const <String>[],
      skills: List<String>.from(
        typeList.map((e) => _decodeHtmlEntities(e.toString())),
      ),
      salary: null,
      timeCommitment: null,
      startDate: startDate,
      endDate: null,
      url: url,
      applicationDeadline: applicationDeadline,
      applicationMethod: 'external',
      applicationUrl: url.isEmpty ? null : url,
      applicationEmail: null,
      contactPersonName: department,
      contactPersonEmail: null,
      contactPersonPhone: null,
      maxApplicants: 0,
      currentApplicants: 0,
      status: 'open',
      isUrgent: false,
      isFeatured: false,
      benefits: const <String>[],
      metadata: <String, dynamic>{
        'campusNames': campusList,
        'campusSlugs': campusSlugs,
        'type': typeList,
        'interests': interestsList,
        'sourceShape': isRawWordPressJob ? 'wordpress_rest' : 'function',
      },
      createdAt: null,
      updatedAt: null,
    );
  }

  factory JobModel.fromMap(Map<String, dynamic> map) {
    return JobModel(
      id: map['\$id'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      department: map['department'] ?? '',
      departmentId: map['department_id'] ?? '',
      departmentLogo: map['department_logo'],
      campusId: map['campus_id'] ?? '',
      type: map['type'] ?? 'volunteer',
      category: map['category'] ?? '',
      requirements: List<String>.from(map['requirements'] ?? []),
      responsibilities: List<String>.from(map['responsibilities'] ?? []),
      skills: List<String>.from(map['skills'] ?? []),
      salary: map['salary'],
      timeCommitment: map['time_commitment'],
      startDate: DateTime.parse(map['start_date']),
      url: map['url']?.toString() ?? '',
      endDate: map['end_date'] != null ? DateTime.parse(map['end_date']) : null,
      applicationDeadline: DateTime.parse(map['application_deadline']),
      applicationMethod: map['application_method'] ?? 'internal',
      applicationUrl: map['application_url'],
      applicationEmail: map['application_email'],
      contactPersonName: map['contact_person_name'] ?? '',
      contactPersonEmail: map['contact_person_email'],
      contactPersonPhone: map['contact_person_phone'],
      maxApplicants: map['max_applicants'] ?? 0,
      currentApplicants: map['current_applicants'] ?? 0,
      status: map['status'] ?? 'open',
      isUrgent: map['is_urgent'] ?? false,
      isFeatured: map['is_featured'] ?? false,
      benefits: List<String>.from(map['benefits'] ?? []),
      metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      createdAt: map['\$createdAt'] != null
          ? DateTime.parse(map['\$createdAt'])
          : null,
      updatedAt: map['\$updatedAt'] != null
          ? DateTime.parse(map['\$updatedAt'])
          : null,
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
    String? slug,
    String? shortDescription,
    bool? cvRequired,
    List<JobQuestionModel>? customQuestions,
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
      slug: slug ?? this.slug,
      shortDescription: shortDescription ?? this.shortDescription,
      cvRequired: cvRequired ?? this.cvRequired,
      customQuestions: customQuestions ?? this.customQuestions,
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
    title,
    description,
    department,
    departmentId,
    departmentLogo,
    campusId,
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
    slug,
    shortDescription,
    cvRequired,
    customQuestions,
  ];

  /// Decode HTML entities from WordPress content
  static String _decodeHtmlEntities(String text) {
    if (text.isEmpty) return text;

    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&ldquo;', '"')
        .replaceAll('&rdquo;', '"')
        .replaceAll('&lsquo;', "'")
        .replaceAll('&rsquo;', "'")
        .replaceAll('&#8211;', '–')
        .replaceAll('&#8217;', "'")
        .replaceAll('&#038;', '&')
        .replaceAll('&hellip;', '…')
        .replaceAll('&copy;', '©')
        .replaceAll('&reg;', '®')
        .replaceAll('&trade;', '™');
  }

  static String _renderedString(dynamic value) {
    if (value == null) return '';
    if (value is Map<String, dynamic>) {
      return (value['rendered'] ?? '').toString();
    }
    return value.toString();
  }

  static List<String> _stringList(dynamic value) {
    if (value == null) return const <String>[];
    if (value is List) {
      return value
          .map((item) => _decodeHtmlEntities(item.toString()).trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    final stringValue = _decodeHtmlEntities(value.toString()).trim();
    return stringValue.isEmpty ? const <String>[] : <String>[stringValue];
  }

  static List<String> _taxonomySlugs(List<String> classList, String prefix) {
    return classList
        .where((item) => item.startsWith(prefix))
        .map((item) => item.substring(prefix.length))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> _taxonomyLabels(List<String> classList, String prefix) {
    return _taxonomySlugs(classList, prefix)
        .map(
          (slug) => slug
              .split('-')
              .where((part) => part.isNotEmpty)
              .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
              .join(' '),
        )
        .toList(growable: false);
  }

  static String? _campusIdFromValues(List<String> values) {
    final normalized = values.map((value) => value.toLowerCase()).join(' ');
    if (normalized.contains('oslo')) return '1';
    if (normalized.contains('bergen')) return '2';
    if (normalized.contains('trondheim')) return '3';
    if (normalized.contains('stavanger')) return '4';
    return null;
  }

  static DateTime? _extractNorwegianDeadline(String html) {
    final plainText = _stripHtml(_decodeHtmlEntities(html));
    final match = RegExp(
      r'Søknadsfrist:\s*(\d{1,2})\.(\d{1,2})\.(\d{4})(?:\s*kl\.?\s*(\d{1,2}):(\d{2}))?',
      caseSensitive: false,
    ).firstMatch(plainText);
    if (match == null) return null;

    final day = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    final year = int.tryParse(match.group(3) ?? '');
    final hour = int.tryParse(match.group(4) ?? '23') ?? 23;
    final minute = int.tryParse(match.group(5) ?? '59') ?? 59;
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day, hour, minute);
  }

  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
