import 'package:biso/core/theme/biso_search_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(ValueChanged<String> onChanged, {bool reducedMotion = false}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: reducedMotion,
          textScaler: const TextScaler.linear(2),
        ),
        child: Scaffold(
          appBar: BisoSearchAppBar(
            title: 'Events',
            hintText: 'Search events',
            onChanged: onChanged,
          ),
          body: ListView(children: const [Text('Campus content')]),
        ),
      ),
    );

void main() {
  testWidgets('search expands in the same toolbar without moving content', (
    tester,
  ) async {
    await tester.pumpWidget(app((_) {}));
    final before = tester.getRect(find.byType(ListView));
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.getRect(find.byType(ListView)), before);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
    expect(find.text('Recent searches'), findsNothing);
  });
  testWidgets(
    'typing is debounced; closing clears and cancels pending search',
    (tester) async {
      final queries = <String>[];
      await tester.pumpWidget(app(queries.add));
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'campus');
      await tester.pump(const Duration(milliseconds: 400));
      expect(queries, ['campus']);
      await tester.enterText(find.byType(TextField), 'party');
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      expect(queries, ['campus', '']);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Events'), findsOneWidget);
    },
  );
  testWidgets('narrow toolbar supports large text and reduced motion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app((_) {}, reducedMotion: true));
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
