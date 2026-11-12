import 'package:biso/data/models/expense_v2_models.dart';
import 'package:biso/presentation/screens/expense/widgets/receipt_notices.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/biso_screen_harness.dart';

ExpenseReceiptDraft _receipt({
  List<String> issues = const [],
  bool duplicate = false,
  double? ocrAmount,
  double? entered = 100,
  String currency = 'NOK',
}) => ExpenseReceiptDraft(
  localId: 'r1',
  fileName: 'r1.jpg',
  mimeType: 'image/jpeg',
  status: ExpenseReceiptStatus.ready,
  amount: entered,
  amountInNok: entered,
  currency: currency,
  receiptIssues: issues,
  possibleDuplicate: duplicate,
  ocrAmount: ocrAmount,
);

Future<void> _pump(
  WidgetTester tester,
  ExpenseReceiptDraft receipt, {
  bool compact = false,
}) => pumpBisoScreen(
  tester,
  Scaffold(
    body: ReceiptNotices(receipt: receipt, compact: compact),
  ),
  inShell: false,
);

void main() {
  testWidgets('notices render issues, duplicate and amount difference', (
    tester,
  ) async {
    await _pump(
      tester,
      _receipt(
        issues: const ['unreadable', 'missing_date', 'something_new'],
        duplicate: true,
        ocrAmount: 120,
      ),
    );
    expect(find.text('Hard to read. A clearer photo helps'), findsOneWidget);
    expect(find.text('No date on the receipt'), findsOneWidget);
    expect(
      find.text('Something looks wrong with this receipt'),
      findsOneWidget,
    );
    expect(
      find.text("This looks like a receipt you've already sent"),
      findsOneWidget,
    );
    expect(
      find.text('The receipt says 120 kr; you entered 100 kr'),
      findsOneWidget,
    );
  });

  testWidgets('a difference of 1 kr or less is not a notice', (tester) async {
    await _pump(tester, _receipt(ocrAmount: 100.8));
    expect(find.byType(Text), findsNothing);
    expect(find.byType(ReceiptNotices), findsOneWidget);
  });

  testWidgets('a foreign-currency receipt gets no amount notice', (
    tester,
  ) async {
    await _pump(tester, _receipt(ocrAmount: 12, currency: 'EUR'));
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('the compact form renders the same sentences', (tester) async {
    await _pump(tester, _receipt(duplicate: true), compact: true);
    expect(
      find.text("This looks like a receipt you've already sent"),
      findsOneWidget,
    );
  });

  testWidgets('Norwegian wording', (tester) async {
    await pumpBisoScreen(
      tester,
      Scaffold(
        body: ReceiptNotices(
          receipt: _receipt(issues: const ['missing_seller'], ocrAmount: 120),
        ),
      ),
      inShell: false,
      locale: const Locale('no'),
    );
    expect(find.text('Kvitteringen mangler selger'), findsOneWidget);
    expect(
      find.text('Kvitteringen viser 120 kr; du har skrevet 100 kr'),
      findsOneWidget,
    );
  });
}
