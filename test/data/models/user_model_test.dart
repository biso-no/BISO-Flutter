import 'package:biso/data/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UserModel reads departments', () {
    final user = UserModel.fromMap({
      r'$id': 'u1',
      'name': 'Kari',
      'email': 'k@example.com',
      'departments': ['d1', 'd2'],
    });

    expect(user.departments, ['d1', 'd2']);
  });

  test('UserModel falls back to legacy department_ids', () {
    final user = UserModel.fromMap({
      r'$id': 'u1',
      'name': 'Kari',
      'email': 'k@example.com',
      'department_ids': ['d3'],
    });

    expect(user.departments, ['d3']);
  });
}
