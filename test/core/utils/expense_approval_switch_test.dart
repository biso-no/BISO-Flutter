import 'package:biso/core/utils/expense_approval_switch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('approvalSwitchFor', () {
    test('an ordinary Oslo department offers the financial-manager switch', () {
      expect(approvalSwitchFor('1', '500'), ApprovalSwitch.financialManager);
      expect(approvalSwitchFor('1', null), ApprovalSwitch.financialManager);
    });

    test('Oslo Drift Campus and Ledelsen offer the controller switch', () {
      expect(approvalSwitchFor('1', '1'), ApprovalSwitch.controller);
      expect(approvalSwitchFor('1', '2'), ApprovalSwitch.controller);
    });

    test('leadership departments on other campuses offer the controller', () {
      expect(approvalSwitchFor('2', '301'), ApprovalSwitch.controller);
      expect(approvalSwitchFor('2', '300'), ApprovalSwitch.controller);
      expect(approvalSwitchFor('3', '600'), ApprovalSwitch.controller);
      expect(approvalSwitchFor('3', '601'), ApprovalSwitch.controller);
      expect(approvalSwitchFor('4', '800'), ApprovalSwitch.controller);
      expect(approvalSwitchFor('4', '801'), ApprovalSwitch.controller);
    });

    test('other departments outside Oslo offer no switch', () {
      expect(approvalSwitchFor('2', '302'), isNull);
      expect(approvalSwitchFor('2', null), isNull);
    });

    test('a leadership department only counts on its own campus', () {
      expect(approvalSwitchFor('2', '600'), isNull);
      expect(approvalSwitchFor('3', '301'), isNull);
    });

    test('national offers no switch', () {
      expect(approvalSwitchFor('5', '1'), isNull);
      expect(approvalSwitchFor('5', '900'), isNull);
    });

    test(
      'National gets the controller switch on Drift BISO and Operations Unit',
      () {
        expect(approvalSwitchFor('5', '1000'), ApprovalSwitch.controller);
        expect(approvalSwitchFor('5', '1002'), ApprovalSwitch.controller);
      },
    );

    test('other National departments get no switch', () {
      expect(approvalSwitchFor('5', '1005'), isNull);
      expect(approvalSwitchFor('5', '1004'), isNull);
      expect(approvalSwitchFor('5', null), isNull);
    });

    test('the National ids do not open a switch on a campus', () {
      expect(approvalSwitchFor('2', '1000'), isNull);
    });
  });
}
