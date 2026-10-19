import 'package:biso/data/models/user_model.dart';
import 'package:biso/presentation/screens/profile/profile_edit_changes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const user = UserModel(
    id: 'u1',
    name: 'Kari',
    email: 'k@example.com',
    phone: '12345678',
    address: 'Gate 1',
    city: 'Oslo',
    zipCode: '0150',
    campusId: 'oslo',
    departments: ['d1', 'd2'],
    bankAccount: '12345678903',
  );

  ProfileEditChanges edit({
    String name = 'Kari',
    String phone = '12345678',
    List<String> departments = const ['d2', 'd1'],
  }) => ProfileEditChanges.from(
    user,
    name: name,
    phone: phone,
    address: 'Gate 1',
    city: 'Oslo',
    zip: '0150',
    campusId: 'oslo',
    departments: departments,
  );

  test('a name-only edit sends only the name', () {
    final changes = edit(name: 'Kari N.');

    expect(changes.name, 'Kari N.');
    expect(changes.departments, isNull);
    expect(changes.phone, isNull);
    expect(changes.address, isNull);
    expect(changes.campusId, isNull);
  });

  test('clearing the phone sends an empty string', () {
    expect(edit(phone: '  ').phone, '');
  });

  test('changing the units sends departments', () {
    expect(edit(departments: ['d1']).departments, ['d1']);
  });
}
