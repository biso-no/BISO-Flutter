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
  final String venue;
  final String? location;
  final String organizerId;
  final String organizerName;
  final String? organizerLogo;
  final String campusId;
  final List<String> categories;
  final List<String> images;
  final int maxAttendees;
  final int currentAttendees;
  final bool isPublic;
  final bool requiresRegistration;
  final double? price;
  final String? registrationUrl;
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
    required this.venue,
    this.location,
    required this.organizerId,
    required this.organizerName,
    this.organizerLogo,
    required this.campusId,
    this.categories = const [],
    this.images = const [],
    this.maxAttendees = 0,
    this.currentAttendees = 0,
    this.isPublic = true,
    this.requiresRegistration = false,
    this.price,
    this.registrationUrl,
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
      venue: map['venue'] ?? '',
      location: map['location'],
      organizerId: map['organizer_id'] ?? '',
      organizerName: map['organizer_name'] ?? '',
      organizerLogo: map['organizer_logo'],
      campusId: map['campus_id'] ?? '',
      categories: List<String>.from(map['categories'] ?? []),
      images: List<String>.from(map['images'] ?? []),
      maxAttendees: map['max_attendees'] ?? 0,
      currentAttendees: map['current_attendees'] ?? 0,
      isPublic: map['is_public'] ?? true,
      requiresRegistration: map['requires_registration'] ?? false,
      price: map['price']?.toDouble(),
      registrationUrl: map['registration_url'],
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
      // `venue`, `organizerId` and `organizerName` are still `required` on the
      // constructor at this point. They have no Appwrite column and Task 7
      // removes them; pass interim values so this task compiles.
      venue: (row['location'] ?? '').toString(),
      organizerId: '',
      organizerName: '',
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
      'venue': venue,
      'location': location,
      'organizer_id': organizerId,
      'organizer_name': organizerName,
      'organizer_logo': organizerLogo,
      'campus_id': campusId,
      'categories': categories,
      'images': images,
      'max_attendees': maxAttendees,
      'current_attendees': currentAttendees,
      'is_public': isPublic,
      'requires_registration': requiresRegistration,
      'price': price,
      'registration_url': registrationUrl,
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
    String? venue,
    String? location,
    String? organizerId,
    String? organizerName,
    String? organizerLogo,
    String? campusId,
    List<String>? categories,
    List<String>? images,
    int? maxAttendees,
    int? currentAttendees,
    bool? isPublic,
    bool? requiresRegistration,
    double? price,
    String? registrationUrl,
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
      venue: venue ?? this.venue,
      location: location ?? this.location,
      organizerId: organizerId ?? this.organizerId,
      organizerName: organizerName ?? this.organizerName,
      organizerLogo: organizerLogo ?? this.organizerLogo,
      campusId: campusId ?? this.campusId,
      categories: categories ?? this.categories,
      images: images ?? this.images,
      maxAttendees: maxAttendees ?? this.maxAttendees,
      currentAttendees: currentAttendees ?? this.currentAttendees,
      isPublic: isPublic ?? this.isPublic,
      requiresRegistration: requiresRegistration ?? this.requiresRegistration,
      price: price ?? this.price,
      registrationUrl: registrationUrl ?? this.registrationUrl,
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
  bool get isFull => maxAttendees > 0 && currentAttendees >= maxAttendees;
  bool get canRegister =>
      isUpcoming &&
      !isFull &&
      (registrationDeadline?.isAfter(DateTime.now()) ?? true);

  @override
  List<Object?> get props => [
    id,
    title,
    description,
    startDate,
    endDate,
    venue,
    location,
    organizerId,
    organizerName,
    organizerLogo,
    campusId,
    categories,
    images,
    maxAttendees,
    currentAttendees,
    isPublic,
    requiresRegistration,
    price,
    registrationUrl,
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
