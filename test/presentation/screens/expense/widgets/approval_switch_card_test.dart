import 'package:biso/core/utils/expense_approval_switch.dart';
import 'package:biso/presentation/screens/expense/widgets/approval_switch_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/biso_screen_harness.dart';

Future<void> _pump(
  WidgetTester tester, {
  required ApprovalSwitch kind,
  required bool value,
  required ValueChanged<bool> onChanged,
}) => pumpBisoScreen(
  tester,
  Scaffold(
    body: ApprovalSwitchCard(kind: kind, value: value, onChanged: onChanged),
  ),
);

void main() {
  testWidgets('the financial-manager card says who approves instead', (
    tester,
  ) async {
    await _pump(
      tester,
      kind: ApprovalSwitch.financialManager,
      value: false,
      onChanged: (_) {},
    );
    expect(
      find.text("I'm this department's financial manager"),
      findsOneWidget,
    );
    expect(
      find.text('Your department manager approves instead'),
      findsOneWidget,
    );
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('the controller card says who approves instead', (tester) async {
    await _pump(
      tester,
      kind: ApprovalSwitch.controller,
      value: false,
      onChanged: (_) {},
    );
    expect(find.text("I'm the campus controller"), findsOneWidget);
    expect(find.text('The campus president approves instead'), findsOneWidget);
  });

  testWidgets('tapping the card reports the new value', (tester) async {
    bool? changed;
    await _pump(
      tester,
      kind: ApprovalSwitch.controller,
      value: false,
      onChanged: (v) => changed = v,
    );
    await tester.tap(find.byType(Switch));
    expect(changed, isTrue);
  });
}
