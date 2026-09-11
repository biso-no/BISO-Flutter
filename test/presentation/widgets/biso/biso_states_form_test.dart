import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {double textScale = 1}) => MaterialApp(
  theme: PremiumTheme.build(Brightness.light),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);

void main() {
  testWidgets('error state offers a localized retry', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      app(BisoErrorState(onRetry: () => retried = true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets('empty state shows its tile, title and message', (tester) async {
    await tester.pumpWidget(
      app(
        const BisoEmptyState(
          icon: CupertinoIcons.calendar,
          accent: BisoAccent.blue,
          title: 'No events',
          message: 'Check back soon',
        ),
      ),
    );
    expect(find.byType(BisoIconTile), findsOneWidget);
    expect(find.text('No events'), findsOneWidget);
    expect(find.text('Check back soon'), findsOneWidget);
  });

  testWidgets('skeletons are static and labelled for screen readers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app(
        const Column(
          children: [
            BisoSkeleton.rows(count: 3),
            BisoSkeleton.grid(count: 4),
            BisoSkeleton.card(),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle(); // would time out if skeletons animated
    expect(find.bySemanticsLabel('Loading'), findsNWidgets(3));
    semantics.dispose();
  });

  testWidgets('form rows label fields and show validation below them', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(
      app(
        Form(
          key: formKey,
          child: Builder(
            builder: (context) => BisoFormGroup(
              title: 'Bank account',
              footer: 'Norwegian accounts have 11 digits',
              children: [
                BisoFormRow(
                  label: 'Account number',
                  child: TextFormField(
                    decoration: bisoInputDecoration(
                      context,
                      hintText: '1234 56 78901',
                    ),
                    validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Account number'), findsOneWidget);
    formKey.currentState!.validate();
    await tester.pump();
    final label = tester.getRect(find.text('Account number'));
    final error = tester.getRect(find.text('Required'));
    expect(error.top, greaterThan(label.bottom));
  });

  testWidgets('bottom bar is a floating surface card', (tester) async {
    await tester.pumpWidget(
      app(BisoBottomBar(child: FilledButton(onPressed: () {}, child: const Text('Buy')))),
    );
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(BisoBottomBar),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect((box.decoration as BoxDecoration).color, BisoPalette.light.surface);
  });

  testWidgets('states and forms fit large text on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        Column(
          children: [
            BisoErrorState(onRetry: () {}),
            const BisoSkeleton.grid(count: 2),
            BisoFormGroup(
              children: [
                BisoFormRow(label: 'Name', child: TextFormField()),
              ],
            ),
          ],
        ),
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
