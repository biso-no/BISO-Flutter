import 'package:biso/presentation/screens/expense/widgets/occasion_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/biso_screen_harness.dart';

Future<void> _pump(WidgetTester tester, {String? errorText}) => pumpBisoScreen(
  tester,
  Scaffold(
    body: OccasionField(
      controller: TextEditingController(),
      focusNode: FocusNode(),
      scrollPadding: const EdgeInsets.all(20),
      errorText: errorText,
    ),
  ),
  inShell: false,
);

void main() {
  testWidgets('the error is the field\'s own and is read with the field', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, errorText: 'Answer this before you submit');

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.errorText, 'Answer this before you submit');
    expect(find.text('Answer this before you submit'), findsOneWidget);
    // The decoration puts its error into the field's own semantics.
    final data = tester
        .getSemantics(find.byType(EditableText))
        .getSemanticsData();
    expect(data.hint, contains('Answer this before you submit'));
    handle.dispose();
  });

  testWidgets('without an error the field has no error text', (tester) async {
    await _pump(tester);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.errorText, isNull);
  });
}
