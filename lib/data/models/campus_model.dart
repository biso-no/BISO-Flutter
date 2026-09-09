import 'package:equatable/equatable.dart';
import 'dart:convert';

class CampusModel extends Equatable {
  final String id;
  final String name;
  final String description;
  final String location;
  final String imageUrl;
  final String heroImageUrl;
  final List<String> benefits;
  final List<String> studentBenefits;
  final List<String> businessBenefits;
  final List<String> careerAdvantages;
  final String? contactEmail;
  final String? contactAddress;
  final WeatherData? weather;
  final CampusStats stats;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CampusModel({
    required this.id,
    required this.name,
    required this.description,
    required this.location,
    required this.imageUrl,
    required this.heroImageUrl,
    this.benefits = const [],
    this.studentBenefits = const [],
    this.businessBenefits = const [],
    this.careerAdvantages = const [],
    this.contactEmail,
    this.contactAddress,
    this.weather,
    required this.stats,
    this.metadata = const {},
    this.createdAt,
    this.updatedAt,
  });

  /// Helper method to extract location string from various formats
  static String _extractLocationString(dynamic locationData) {
    if (locationData == null) return '';
    
    if (locationData is String) {
      final trimmed = locationData.trim();
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map<String, dynamic>) {
            return decoded['address']?.toString() ?? '';
          }
        } catch (_) {}
      }
      return locationData;
    }
    
    if (locationData is Map<String, dynamic>) {
      // Extract address from the location object
      return locationData['address']?.toString() ?? '';
    }
    
    // Fallback for any other type
    return locationData.toString();
  }

  factory CampusModel.fromMap(Map<String, dynamic> map) {
    return CampusModel(
      id: map['\$id'] ?? map['id'] ?? '',
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      location: _extractLocationString(map['location']),
      imageUrl: map['image_url'] ?? '',
      heroImageUrl: map['hero_image_url'] ?? '',
      benefits: List<String>.from(map['benefits'] ?? []),
      studentBenefits: List<String>.from(map['student_benefits'] ?? []),
      businessBenefits: List<String>.from(map['business_benefits'] ?? []),
      careerAdvantages: List<String>.from(map['career_advantages'] ?? []),
      contactEmail: map['contact_email'],
      contactAddress: map['contact_address'],
      weather: map['weather'] != null
          ? WeatherData.fromMap(map['weather'])
          : null,
      stats: CampusStats.fromMap(map['stats'] ?? {}),
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
      'name': name,
      'description': description,
      'location': location,
      'image_url': imageUrl,
      'hero_image_url': heroImageUrl,
      'benefits': benefits,
      'student_benefits': studentBenefits,
      'business_benefits': businessBenefits,
      'career_advantages': careerAdvantages,
      'contact_email': contactEmail,
      'contact_address': contactAddress,
      'weather': weather?.toMap(),
      'stats': stats.toMap(),
      'metadata': metadata,
    };
  }

  CampusModel copyWith({
    String? id,
    String? name,
    String? description,
    String? location,
    String? imageUrl,
    String? heroImageUrl,
    List<String>? benefits,
    List<String>? studentBenefits,
    List<String>? businessBenefits,
    List<String>? careerAdvantages,
    String? contactEmail,
    String? contactAddress,
    WeatherData? weather,
    CampusStats? stats,
    Map<String, dynamic>? metadata,
  }) {
    return CampusModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      location: location ?? this.location,
      imageUrl: imageUrl ?? this.imageUrl,
      heroImageUrl: heroImageUrl ?? this.heroImageUrl,
      benefits: benefits ?? this.benefits,
      studentBenefits: studentBenefits ?? this.studentBenefits,
      businessBenefits: businessBenefits ?? this.businessBenefits,
      careerAdvantages: careerAdvantages ?? this.careerAdvantages,
      contactEmail: contactEmail ?? this.contactEmail,
      contactAddress: contactAddress ?? this.contactAddress,
      weather: weather ?? this.weather,
      stats: stats ?? this.stats,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    description,
    location,
    imageUrl,
    heroImageUrl,
    benefits,
    studentBenefits,
    businessBenefits,
    careerAdvantages,
    contactEmail,
    contactAddress,
    weather,
    stats,
    metadata,
    createdAt,
    updatedAt,
  ];
}

class WeatherData extends Equatable {
  final double temperature;
  final String condition;
  final String icon;
  final int humidity;
  final double windSpeed;

  const WeatherData({
    required this.temperature,
    required this.condition,
    required this.icon,
    required this.humidity,
    required this.windSpeed,
  });

  factory WeatherData.fromMap(Map<String, dynamic> map) {
    return WeatherData(
      temperature: (map['temperature'] ?? 0).toDouble(),
      condition: map['condition'] ?? '',
      icon: map['icon'] ?? '',
      humidity: map['humidity'] ?? 0,
      windSpeed: (map['wind_speed'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'temperature': temperature,
      'condition': condition,
      'icon': icon,
      'humidity': humidity,
      'wind_speed': windSpeed,
    };
  }

  @override
  List<Object?> get props => [
    temperature,
    condition,
    icon,
    humidity,
    windSpeed,
  ];
}

class CampusStats extends Equatable {
  final int activeEvents;
  final int availableJobs;
  final int marketplaceItems;
  final int departmentsCount;

  const CampusStats({
    this.activeEvents = 0,
    this.availableJobs = 0,
    this.marketplaceItems = 0,
    this.departmentsCount = 0,
  });

  factory CampusStats.fromMap(Map<String, dynamic> map) {
    return CampusStats(
      activeEvents: map['active_events'] ?? 0,
      availableJobs: map['available_jobs'] ?? 0,
      marketplaceItems: map['marketplace_items'] ?? 0,
      departmentsCount: map['departments_count'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'active_events': activeEvents,
      'available_jobs': availableJobs,
      'marketplace_items': marketplaceItems,
      'departments_count': departmentsCount,
    };
  }

  @override
  List<Object?> get props => [
    activeEvents,
    availableJobs,
    marketplaceItems,
    departmentsCount,
  ];
}
