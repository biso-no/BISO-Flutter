import 'package:equatable/equatable.dart';

import '../../core/utils/appwrite_image.dart';
import '../../core/utils/localized_content.dart';
import 'content_translation.dart';

class EventModel extends Equatable {
  final String id;
  final String title;
  final String description;
  final DateTime startDate;
  final DateTime? endDate;
  final String? location;
  final String campusId;
  final List<String> images;
  final double? price;
  final DateTime? registrationDeadline;
  final String status; // 'upcoming', 'ongoing', 'completed', 'cancelled'
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // --- new schema-backed fields ---
  final String? slug;
  final String? shortDescription;
  final String? ticketUrl;
  final String? locationMode;
  final String? onlineUrl;
  final String? category;
  final String? coverPattern;
  final String? pricingMode;
  final String? departmentId;
  final String? contactName;
  final String? contactRole;
  final String? contactEmail;
  final double? memberPrice;
  final bool memberOnly;
  final bool waitlist;
  final int capacity;
  final List<String> tags;

  const EventModel({
    required this.id,
    required this.title,
    required this.description,
    required this.startDate,
    this.endDate,
    this.location,
    required this.campusId,
    this.images = const [],
    this.price,
    this.registrationDeadline,
    this.status = 'upcoming',
    this.createdAt,
    this.updatedAt,
    this.slug,
    this.shortDescription,
    this.ticketUrl,
    this.locationMode,
    this.onlineUrl,
    this.category,
    this.coverPattern,
    this.pricingMode,
    this.departmentId,
    this.contactName,
    this.contactRole,
    this.contactEmail,
    this.memberPrice,
    this.memberOnly = false,
    this.waitlist = false,
    this.capacity = 0,
    this.tags = const [],
  });

  factory EventModel.fromMap(Map<String, dynamic> map) {
    return EventModel(
      id: map['\$id'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      startDate: DateTime.parse(map['start_date']),
      endDate: map['end_date'] != null ? DateTime.parse(map['end_date']) : null,
      location: map['location'],
      campusId: map['campus_id'] ?? '',
      images: List<String>.from(map['images'] ?? []),
      price: map['price']?.toDouble(),
      registrationDeadline: map['registration_deadline'] != null
          ? DateTime.parse(map['registration_deadline'])
          : null,
      status: map['status'] ?? 'upcoming',
      createdAt: map['\$createdAt'] != null
          ? DateTime.parse(map['\$createdAt'])
          : null,
      updatedAt: map['\$updatedAt'] != null
          ? DateTime.parse(map['\$updatedAt'])
          : null,
    );
  }

  factory EventModel.fromAppwriteRow(
    Map<String, dynamic> row, {
    String locale = 'no',
  }) {
    final translations = ContentTranslation.listFrom(row['translation_refs']);
    final content = resolveLocalizedContent(translations, locale);
    final image = appwriteImageUrl(row['image']);

    DateTime? parseDate(Object? v) {
      final s = v?.toString();
      if (s == null || s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    return EventModel(
      id: (row[r'$id'] ?? '').toString(),
      slug: row['slug']?.toString(),
      title: content.title,
      description: content.description,
      shortDescription: content.shortDescription,
      // `start_date` is `required=False` in the live schema, so a missing or
      // unparseable value is a legal (if malformed) row, not an error. Fall
      // back to the Unix epoch (UTC) rather than `DateTime.now()`: sorting a
      // broken event to the far past keeps it out of "upcoming"/"live"
      // filtering instead of making it masquerade as happening right now.
      // Do NOT "fix" this back to `DateTime.now()`.
      startDate: parseDate(row['start_date']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      endDate: parseDate(row['end_date']),
      registrationDeadline: parseDate(row['registration_deadline']),
      campusId: (row['campus_id'] ?? '').toString(),
      departmentId: row['department_id']?.toString(),
      location: row['location']?.toString(),
      locationMode: row['location_mode']?.toString(),
      onlineUrl: row['online_url']?.toString(),
      images: image == null ? const <String>[] : <String>[image],
      price: (row['price'] as num?)?.toDouble(),
      memberPrice: (row['member_price'] as num?)?.toDouble(),
      pricingMode: row['pricing_mode']?.toString(),
      memberOnly: row['member_only'] == true,
      capacity: (row['capacity'] as num?)?.toInt() ?? 0,
      waitlist: row['waitlist'] == true,
      category: row['category']?.toString(),
      coverPattern: row['cover_pattern']?.toString(),
      tags: (row['tags'] is List)
          ? (row['tags'] as List).map((e) => e.toString()).toList(growable: false)
          : const <String>[],
      ticketUrl: row['ticket_url']?.toString(),
      contactName: row['contact_name']?.toString(),
      contactRole: row['contact_role']?.toString(),
      contactEmail: row['contact_email']?.toString(),
      status: (row['status'] ?? 'published').toString(),
      createdAt: parseDate(row[r'$createdAt']),
      updatedAt: parseDate(row[r'$updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'location': location,
      'campus_id': campusId,
      'images': images,
      'price': price,
      'registration_deadline': registrationDeadline?.toIso8601String(),
      'status': status,
    };
  }

  EventModel copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    String? location,
    String? campusId,
    List<String>? images,
    double? price,
    DateTime? registrationDeadline,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EventModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      location: location ?? this.location,
      campusId: campusId ?? this.campusId,
      images: images ?? this.images,
      price: price ?? this.price,
      registrationDeadline: registrationDeadline ?? this.registrationDeadline,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isUpcoming => status == 'upcoming';
  bool get isOngoing => status == 'ongoing';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';
  bool get canRegister =>
      isUpcoming && (registrationDeadline?.isAfter(DateTime.now()) ?? true);

  @override
  List<Object?> get props => [
    id,
    title,
    description,
    startDate,
    endDate,
    location,
    campusId,
    images,
    price,
    registrationDeadline,
    status,
    createdAt,
    updatedAt,
    slug,
    shortDescription,
    ticketUrl,
    locationMode,
    onlineUrl,
    category,
    coverPattern,
    pricingMode,
    departmentId,
    contactName,
    contactRole,
    contactEmail,
    memberPrice,
    memberOnly,
    waitlist,
    capacity,
    tags,
  ];
}
