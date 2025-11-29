class DepartmentModel {
  final String id;
  final String name;
  final String campusId;
  final String? logo;
  final bool active;
  final String? type;
  final String? description;

  DepartmentModel({
    required this.id,
    required this.name,
    required this.campusId,
    required this.active,
    this.logo,
    this.type,
    this.description,
  });

  factory DepartmentModel.fromMap(Map<String, dynamic> map) {
    return DepartmentModel(
      id: (map['\$id'] ?? map['Id'] ?? '').toString(),
      name: (map['Name'] ?? map['name'] ?? '').toString(),
      campusId: (map['campus_id'] ?? '').toString(),
      active: (map['active'] is bool)
          ? map['active'] as bool
          : (map['active']?.toString() == 'true'),
      logo: (map['logo']?.toString().isNotEmpty ?? false)
          ? map['logo'].toString()
          : null,
      type: (map['type']?.toString().isNotEmpty ?? false)
          ? map['type'].toString()
          : null,
      description: (map['description']?.toString().isNotEmpty ?? false)
          ? map['description'].toString()
          : null,
    );
  }

  factory DepartmentModel.fromTranslationMap(Map<String, dynamic> map) {
    final dept = map['department_ref'] as Map<String, dynamic>? ?? {};
    return DepartmentModel(
      id: (dept['\$id'] ?? dept['Id'] ?? '').toString(),
      name: (map['title'] ?? '').toString(), // Use translated title as name
      campusId: (dept['campus_id'] ?? '').toString(),
      active: (dept['active'] is bool)
          ? dept['active'] as bool
          : (dept['active']?.toString() == 'true'),
      logo: (dept['logo']?.toString().isNotEmpty ?? false)
          ? dept['logo'].toString()
          : null,
      type: (dept['type']?.toString().isNotEmpty ?? false)
          ? dept['type'].toString()
          : null,
      description: (map['description']?.toString().isNotEmpty ?? false)
          ? map['description'].toString()
          : null,
    );
  }
}
