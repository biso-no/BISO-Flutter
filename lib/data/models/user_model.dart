import 'package:equatable/equatable.dart';

import '../../core/logging/print_migration.dart';

class UserModel extends Equatable {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? address;
  final String? city;
  final String? zipCode;
  final String? campusId;
  final String? studentId;
  final List<String> departments;
  final String? avatarUrl;
  final String? bankAccount;
  final String? swift;
  final bool? isPublic; // null = not set, false = private, true = public
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.address,
    this.city,
    this.zipCode,
    this.campusId,
    this.studentId,
    this.departments = const [],
    this.avatarUrl,
    this.bankAccount,
    this.swift,
    this.isPublic,
    this.createdAt,
    this.updatedAt,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    logPrint('🔍 UserModel.fromMap - Raw map keys: ${map.keys.toList()}');

    return UserModel(
      id: map['\$id'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'],
      address: map['address'],
      city: map['city'],
      zipCode: map['zip'],
      campusId: map['campus_id'],
      studentId:
          map['student_id'], // Use the direct string field, not the relationship
      departments: _parseDepartmentIds(
        map['departments'] ?? map['department_ids'],
      ), // the server writes `departments`; `department_ids` is legacy
      avatarUrl: map['avatar'],
      bankAccount: map['bank_account'],
      swift: map['swift'],
      isPublic: map['is_public'], // Can be null for existing users
      createdAt: map['\$createdAt'] != null
          ? DateTime.parse(map['\$createdAt'])
          : null,
      updatedAt: map['\$updatedAt'] != null
          ? DateTime.parse(map['\$updatedAt'])
          : null,
    );
  }

  factory UserModel.fromDocument(dynamic document) {
    if (document is Map<String, dynamic>) {
      return UserModel.fromMap(document);
    }
    return UserModel.fromMap(document.data);
  }

  // Helper method to safely parse department IDs
  static List<String> _parseDepartmentIds(dynamic departmentIds) {
    if (departmentIds == null) return <String>[];
    if (departmentIds is List) {
      return departmentIds
          .map((e) => e?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (departmentIds is String) {
      return [departmentIds];
    }
    return <String>[];
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'address': address,
      'city': city,
      'zip': zipCode,
      'campus_id': campusId,
      'student_id': studentId,
      'departments': departments,
      'avatar': avatarUrl,
      'bank_account': bankAccount,
      'swift': swift,
      'is_public': isPublic,
    };
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? address,
    String? city,
    String? zipCode,
    String? campusId,
    String? studentId,
    List<String>? departments,
    String? avatarUrl,
    String? bankAccount,
    String? swift,
    bool? isPublic,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      city: city ?? this.city,
      zipCode: zipCode ?? this.zipCode,
      campusId: campusId ?? this.campusId,
      studentId: studentId ?? this.studentId,
      departments: departments ?? this.departments,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bankAccount: bankAccount ?? this.bankAccount,
      swift: swift ?? this.swift,
      isPublic: isPublic ?? this.isPublic,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    email,
    phone,
    address,
    city,
    zipCode,
    campusId,
    studentId,
    departments,
    avatarUrl,
    bankAccount,
    swift,
    isPublic,
    createdAt,
    updatedAt,
  ];
}
