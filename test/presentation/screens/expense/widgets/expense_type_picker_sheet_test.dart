import 'dart:async';
import 'dart:ui' as ui;

import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/models/expense_cost_type_option.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/screens/expense/widgets/expense_type_picker_sheet.dart';
import 'package:biso/providers/expense/expense_provider.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Opens the sheet from a button and records what it returned.
Future<ValueNotifier<ExpenseTypeChoice?>> _open(
  WidgetTester tester, {
  List<ExpenseCostTypeOption>? types = const [_food, _travel],
  String? currentSlug,
  ReloadExpenseTypes? onRetry,
  bool loading = false,
  String? headerMessage,
}) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final result = ValueNotifier<ExpenseTypeChoice?>(null);
  await tester.pumpWidget(
    MaterialApp(
      theme: PremiumTheme.build(Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result.value = await showExpenseTypePicker(
                context,
                types: types,
                currentSlug: currentSlug,
                onRetry: onRetry,
                loading: loading,
                headerMessage: headerMessage,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

Future<void> _enter(WidgetTester tester) async {
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('enter on an exact name picks the type', (tester) async {
    final result = await _open(tester);
    await _type(tester, 'food and drink');
    await _enter(tester);
    expect(result.value, isA<PickedType>());
    expect((result.value! as PickedType).slug, 'food');
  });

  testWidgets('enter on other text uses own text', (tester) async {
    final result = await _open(tester);
    await _type(tester, '  Stage smoke ');
    await _enter(tester);
    expect(result.value, isA<OwnText>());
    expect((result.value! as OwnText).text, 'Stage smoke');
  });

  testWidgets('the own-text row appears only without an exact match', (
    tester,
  ) async {
    await _open(tester);
    expect(find.textContaining('Use "'), findsNothing);
    await _type(tester, 'Travel');
    expect(find.textContaining('Use "'), findsNothing);
    await _type(tester, 'Trav');
    expect(find.text('Use "Trav"'), findsOneWidget);
    expect(
      find.text('Finance will place it under the right type.'),
      findsOneWidget,
    );
  });

  testWidgets('tapping the own-text row returns the typed words', (
    tester,
  ) async {
    final result = await _open(tester);
    await _type(tester, 'Stage smoke');
    await tester.tap(find.text('Use "Stage smoke"'));
    await tester.pumpAndSettle();
    expect((result.value! as OwnText).text, 'Stage smoke');
  });

  testWidgets('the search filters the list and the current type is checked', (
    tester,
  ) async {
    await _open(tester, currentSlug: 'travel');
    expect(find.byIcon(CupertinoIcons.checkmark), findsOneWidget);
    await _type(tester, 'food');
    expect(find.text('Travel'), findsNothing);
    expect(find.text('Food and drink'), findsOneWidget);
  });

  testWidgets('a load error offers retry, and a retry that works lists types', (
    tester,
  ) async {
    await _open(tester, types: null, onRetry: () async => const [_food]);
    expect(find.text("Couldn't load expense types"), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Food and drink'), findsOneWidget);
  });

  testWidgets('no types shows the empty state', (tester) async {
    await _open(tester, types: const []);
    expect(find.text('No expense types available.'), findsOneWidget);
  });

  testWidgets('the current row reports selected in the semantics tree', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _open(tester, currentSlug: 'travel');
    final selectedRow = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.selected == true,
    );
    expect(selectedRow, findsOneWidget);
    expect(
      find.descendant(of: selectedRow, matching: find.text('Travel')),
      findsOneWidget,
    );
    final data = tester.getSemantics(selectedRow).getSemanticsData();
    expect(data.flagsCollection.isSelected, ui.Tristate.isTrue);
    handle.dispose();
  });

  testWidgets('the search field has an accessible label', (tester) async {
    final handle = tester.ensureSemantics();
    await _open(tester);
    expect(find.bySemanticsLabel('Search expense types'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('while loading the sheet shows a spinner, no error and no '
      'retry', (tester) async {
    await tester.runAsync(() async {});
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: PremiumTheme.build(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showExpenseTypePicker(
                context,
                types: null,
                loading: true,
                onRetry: () async => null,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text("Couldn't load expense types"), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('a header message sits under the title', (tester) async {
    await _open(tester, headerMessage: 'Choose a type for 2 receipts');
    expect(find.text('Expense type'), findsOneWidget);
    expect(find.text('Choose a type for 2 receipts'), findsOneWidget);
  });

  testWidgets('without a header message there is no extra line', (
    tester,
  ) async {
    await _open(tester);
    expect(find.textContaining('Choose a type'), findsNothing);
  });

  testWidgets('a sheet opened while loading fills in when the types arrive', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final completer = Completer<List<ExpenseCostTypeOption>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expenseCostTypesProvider.overrideWith((ref) => completer.future),
        ],
        child: MaterialApp(
          theme: PremiumTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              final state = ref.watch(expenseCostTypesProvider);
              return Scaffold(
                body: TextButton(
                  // Opened with what the screen had at that moment.
                  onPressed: () => showExpenseTypePicker(
                    context,
                    types: state.value,
                    loading: state.isLoading,
                  ),
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(const [_food, _travel]);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Food and drink'), findsOneWidget);
    expect(find.text('Travel'), findsOneWidget);
  });
}
