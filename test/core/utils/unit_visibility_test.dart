import 'package:biso/core/utils/unit_visibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isPublicUnitName', () {
    test('hides every operating ledger, including ones no campus has yet', () {
      expect(isPublicUnitName('Drift BISO'), false);
      expect(isPublicUnitName('Drift Campus Oslo'), false);
      expect(isPublicUnitName('Drift Campus Bergen'), false);
      expect(isPublicUnitName('Drift Campus Trondheim'), false);
      expect(isPublicUnitName('Drift Campus Stavanger'), false);
      expect(isPublicUnitName('Drift Campus Kristiansand'), false);
    });

    test('hides national accounting entities', () {
      expect(isPublicUnitName('Accounting Departement'), false);
      expect(isPublicUnitName('Student groups outside BISO (gift fund)'), false);
      expect(isPublicUnitName('Samlinger - CL'), false);
      expect(isPublicUnitName('Investment Committee'), false);
    });

    test('hides governance bodies that /campus already presents', () {
      expect(isPublicUnitName('Board'), false);
      expect(isPublicUnitName('Operations Unit'), false);
      expect(isPublicUnitName('Control Committee'), false);
      expect(isPublicUnitName('HR'), false);
      expect(isPublicUnitName('Organisasjonsstrukturkomiteen'), false);
    });

    test('keeps real student units', () {
      expect(isPublicUnitName('OSL Fadderullan'), true);
      expect(isPublicUnitName('BRG Case Club'), true);
      expect(isPublicUnitName('TRD Society'), true);
      expect(isPublicUnitName('Wintergames'), true);
      expect(isPublicUnitName('Alumni'), true);
    });

    test('matches the denylist without stripping the campus prefix', () {
      expect(isPublicUnitName('OSL Board'), true);
      expect(isPublicUnitName('BRG HR'), true);
      expect(isPublicUnitName('TRD Administration'), true);
    });

    test('does not hide a unit merely starting with the letters d-r-i-f-t', () {
      expect(isPublicUnitName('Driftige Studenter'), true);
    });

    test('is case- and whitespace-insensitive', () {
      expect(isPublicUnitName('  drift   biso '), false);
      expect(isPublicUnitName('OPERATIONS  UNIT'), false);
    });

    test('rejects a missing or blank name', () {
      expect(isPublicUnitName(null), false);
      expect(isPublicUnitName('   '), false);
    });
  });

  group('isPublicUnit', () {
    test('requires the row not to be explicitly inactive', () {
      expect(isPublicUnit(name: 'OSL Media', active: true), true);
      expect(isPublicUnit(name: 'OSL Media', active: false), false);
    });

    test('treats a null active as active', () {
      expect(isPublicUnit(name: 'OSL Media', active: null), true);
    });

    test('still hides a ledger that is active', () {
      expect(isPublicUnit(name: 'Drift BISO', active: true), false);
    });
  });
}
