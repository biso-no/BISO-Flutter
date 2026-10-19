import '../../../data/models/user_model.dart';

/// The profile fields a student actually changed. A null field is not sent
/// to `PUT /api/profile`; an empty string clears a text field.
class ProfileEditChanges {
  const ProfileEditChanges({
    this.name,
    this.phone,
    this.address,
    this.city,
    this.zipCode,
    this.campusId,
    this.departments,
  });

  final String? name;
  final String? phone;
  final String? address;
  final String? city;
  final String? zipCode;
  final String? campusId;
  final List<String>? departments;

  /// Compares the form values with [user] and keeps only what differs.
  factory ProfileEditChanges.from(
    UserModel user, {
    required String name,
    required String phone,
    required String address,
    required String city,
    required String zip,
    required String? campusId,
    required List<String> departments,
  }) {
    String? text(String entered, String? current) {
      final value = entered.trim();
      return value == (current ?? '') ? null : value;
    }

    final before = {...user.departments};
    final unchangedDepartments =
        before.length == departments.toSet().length &&
        before.containsAll(departments);

    return ProfileEditChanges(
      name: text(name, user.name),
      phone: text(phone, user.phone),
      address: text(address, user.address),
      city: text(city, user.city),
      zipCode: text(zip, user.zipCode),
      campusId: campusId == user.campusId ? null : campusId,
      departments: unchangedDepartments ? null : departments,
    );
  }
}
