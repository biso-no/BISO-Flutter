import 'package:biso/core/theme/biso_colors.dart';
import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/core/utils/expense_type_state.dart';
import 'package:biso/data/models/expense_cost_type_option.dart';
import 'package:biso/data/models/expense_v2_models.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/screens/expense/widgets/receipt_type_chip.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _food = ExpenseCostTypeOption(
  slug: 'food',
  label: 'Food and drink',
  labelNo: 'Mat og drikke',
  sortOrder: 1,
);
const _travel = ExpenseCostTypeOption(
  slug: 'travel',
  label: 'Travel',
  labelNo: 'Reise',
  sortOrder: 2,
);
const _types = [_food, _travel];

ExpenseReceiptDraft _receipt() => const ExpenseReceiptDraft(
  localId: 'r1',
  fileName: 'receipt.jpg',
  mimeType: 'image/jpeg',
  amount: 120,
);

/// Hosts the chip, keeping the receipt it reports so a test can read it back.
class _Host extends StatefulWidget {
  const _Host({required this.initial, required this.types});

  final ExpenseReceiptDraft initial;
  final List<ExpenseCostTypeOption>? types;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late ExpenseReceiptDraft receipt = widget.initial;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ReceiptTypeChip(
        receipt: receipt,
        types: widget.types,
        onChanged: (updated) => setState(() => receipt = updated),
      ),
    ),
  );
}

Future<_HostState> _pump(
  WidgetTester tester, {
  ExpenseReceiptDraft? receipt,
  List<ExpenseCostTypeOption>? types = _types,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: PremiumTheme.build(Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: _Host(initial: receipt ?? _receipt(), types: types),
    ),
  );
  await tester.pump();
  return tester.state<_HostState>(find.byType(_Host));
}

void main() {
  testWidgets('the chip shows needs-a-choice in the attention colour', (
    tester,
  ) async {
    await _pump(tester);
    final label = find.text('Choose a type');
    expect(label, findsOneWidget);
    final palette = BisoPalette.of(tester.element(label));
    expect(tester.widget<Text>(label).style?.color, palette.warning);
  });

  testWidgets('the chip meets a 48 dp tap target and a semantics label', (
    tester,
  ) async {
    await _pump(tester);
    expect(
      tester.getSize(find.byType(InkWell)).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      find.bySemanticsLabel('Expense type needed. Tap to choose.'),
      findsOneWidget,
    );
  });

  testWidgets('the chip shows the AI pick with a sparkle and a tooltip', (
    tester,
  ) async {
    await _pump(
      tester,
      receipt: _receipt().copyWith(
        costType: 'food',
        typeState: ExpenseTypeState.aiPicked,
      ),
    );
    expect(find.text('Food and drink'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.sparkles), findsOneWidget);
    expect(find.byTooltip('Picked by AI — tap to change'), findsOneWidget);
  });

  testWidgets('the chip shows own text in quotes', (tester) async {
    await _pump(tester, receipt: _receipt().useOwnText('Stage smoke'));
    expect(find.text('“Stage smoke”'), findsOneWidget);
  });

  testWidgets('the chip shows the label in Norwegian', (tester) async {
    await _pump(
      tester,
      receipt: _receipt().chooseType('food'),
      locale: const Locale('no'),
    );
    expect(find.text('Mat og drikke'), findsOneWidget);
  });

  testWidgets('the chip is absent for a receipt that takes no type', (
    tester,
  ) async {
    await _pump(
      tester,
      receipt: _receipt().copyWith(documentType: 'bank-statement'),
    );
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('tapping the chip opens the sheet and applies the choice', (
    tester,
  ) async {
    final host = await _pump(tester);
    await tester.tap(find.text('Choose a type'));
    await tester.pumpAndSettle();
    expect(find.text('Travel'), findsOneWidget);
    await tester.tap(find.text('Travel'));
    await tester.pumpAndSettle();
    expect(host.receipt.costType, 'travel');
    expect(host.receipt.typeState, ExpenseTypeState.chosen);
    expect(find.text('Travel'), findsOneWidget);
  });

  testWidgets('with no types the chip keeps the stored choice and the sheet '
      'offers retry', (tester) async {
    await _pump(tester, receipt: _receipt().chooseType('food'), types: null);
    expect(find.text('food'), findsOneWidget);
    await tester.tap(find.text('food'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load expense types"), findsOneWidget);
  });
}
