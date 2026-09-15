import 'package:biso/core/utils/department_name.dart';
import 'package:biso/data/models/department_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('displayDepartmentName', () {
    test('strips the 24SevenOffice campus code', () {
      expect(displayDepartmentName('BRG Aksjeklubben'), 'Aksjeklubben');
      expect(displayDepartmentName('OSL BBA - Bachelor'), 'BBA - Bachelor');
      expect(displayDepartmentName('TRD Fotball'), 'Fotball');
      expect(displayDepartmentName('STV HR'), 'HR');
    });

    test('leaves names without a campus code alone', () {
      expect(
        displayDepartmentName('Drift Campus Bergen'),
        'Drift Campus Bergen',
      );
      expect(displayDepartmentName('OSLO Society'), 'OSLO Society');
      expect(displayDepartmentName('Brg lowercase'), 'Brg lowercase');
    });

    test('strips only one code and never empties the name', () {
      expect(displayDepartmentName('BRG BRG Test'), 'BRG Test');
      expect(displayDepartmentName('OSL'), 'OSL');
      expect(displayDepartmentName('OSL   '), 'OSL   ');
    });
  });

  test('DepartmentModel displays names without the campus code', () {
    expect(
      DepartmentModel.fromMap({'\$id': '1', 'Name': 'BRG Beats'}).name,
      'Beats',
    );
    expect(
      DepartmentModel.fromTranslationMap({
        'title': 'OSL Careerdays',
        'department_ref': {'\$id': '25'},
      }).name,
      'Careerdays',
    );
  });
}
