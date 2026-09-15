import 'package:biso/data/services/department_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DepartmentService.mergeTranslations', () {
    final departments = [
      {
        '\$id': '4',
        'Name': 'Business Society',
        'campus_id': '1',
        'active': true,
      },
      {
        '\$id': '2',
        'Name': 'Drift Campus Oslo',
        'campus_id': '1',
        'active': true,
      },
    ];

    test('keeps departments that have no translation row', () {
      final result = DepartmentService.mergeTranslations(departments, const []);

      expect(result.map((d) => d.id), ['4', '2']);
      expect(result.map((d) => d.name), [
        'Business Society',
        'Drift Campus Oslo',
      ]);
    });

    test('uses the translated title and description when present', () {
      final result = DepartmentService.mergeTranslations(departments, [
        {
          'title': 'Campus Management Oslo',
          'description': '<p>Runs the campus</p>',
          'department_ref': {'\$id': '2'},
        },
      ]);

      final translated = result.firstWhere((d) => d.id == '2');
      expect(translated.name, 'Campus Management Oslo');
      expect(translated.description, '<p>Runs the campus</p>');
      expect(translated.campusId, '1');
      expect(result.firstWhere((d) => d.id == '4').name, 'Business Society');
    });

    test('sorts by the displayed name', () {
      final result = DepartmentService.mergeTranslations(departments, [
        {
          'title': 'Zeta',
          'department_ref': {'\$id': '2'},
        },
      ]);

      expect(result.map((d) => d.name), ['Business Society', 'Zeta']);
    });
  });
}
