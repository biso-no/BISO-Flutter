import 'package:biso/core/theme/biso_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:ui' show SemanticsAction;

const tabs = [
  BisoNavDestination(icon: Icons.home_outlined, label: 'Home'),
  BisoNavDestination(icon: Icons.explore_outlined, label: 'Explore'),
  BisoNavDestination(icon: Icons.person_outline, label: 'Profile'),
];

Widget app({
  int index = 0,
  bool accessible = false,
  double keyboard = 0,
  bool horizontal = false,
  bool reducedMotion = false,
  double textScale = 1,
  ValueChanged<int>? onSelected,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 844),
        padding: const EdgeInsets.only(bottom: 34),
        viewPadding: const EdgeInsets.only(bottom: 34),
        viewInsets: EdgeInsets.only(bottom: keyboard),
        accessibleNavigation: accessible,
        disableAnimations: reducedMotion,
        textScaler: TextScaler.linear(textScale),
      ),
      child: BisoNavigationScaffold(
        currentIndex: index,
        routeKey: '$index',
        destinations: tabs,
        onSelected: onSelected ?? (_) {},
        child: Builder(
          builder: (context) => Scaffold(
            body: ListView.builder(
              scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
              padding: horizontal
                  ? EdgeInsets.zero
                  : BisoNavigationInset.padding(
                      context,
                      const EdgeInsets.only(bottom: 16),
                    ),
              itemExtent: 80,
              itemCount: 30,
              itemBuilder: (_, i) => Text('Item $i', key: ValueKey('item-$i')),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('scroll viewport extends behind the floating navigation', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    final viewport = tester.getRect(find.byType(ListView));
    final nav = tester.getRect(find.byKey(const ValueKey('biso-nav-expanded')));
    expect(
      viewport.bottom,
      tester.view.physicalSize.height / tester.view.devicePixelRatio,
    );
    expect(viewport.bottom, greaterThan(nav.bottom));
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    scrollable.position.jumpTo(200);
    await tester.pumpAndSettle();
    final compact = tester.getRect(
      find.byKey(const ValueKey('biso-nav-collapsed')),
    );
    final visibleRows = tester
        .widgetList<Text>(find.byType(Text))
        .where(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('item-'),
        );
    expect(
      visibleRows.any(
        (w) => tester.getRect(find.byKey(w.key!)).overlaps(compact),
      ),
      isTrue,
    );
  });

  testWidgets('screen readers can activate every tab', (tester) async {
    final semantics = tester.ensureSemantics();
    final selections = <int>[];
    await tester.pumpWidget(app(onSelected: selections.add));
    for (var i = 0; i < tabs.length; i++) {
      final node = tester.getSemantics(find.bySemanticsLabel(tabs[i].label));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      node.owner!.performAction(node.id, SemanticsAction.tap);
    }
    semantics.dispose();
    expect(selections, [0, 1, 2]);
  });
  testWidgets('down scroll collapses; tapping active tab expands', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('biso-nav-collapsed')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('biso-nav-collapsed')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('biso-nav-expanded')), findsOneWidget);
  });

  testWidgets('scrolling back up expands navigation', (tester) async {
    await tester.pumpWidget(app());
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('biso-nav-expanded')), findsOneWidget);
  });

  testWidgets('last list item clears navigation even in a nested Scaffold', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('biso-nav-collapsed')));
    await tester.pumpAndSettle();
    final last = tester.getRect(find.byKey(const ValueKey('item-29')));
    final nav = tester.getRect(find.byKey(const ValueKey('biso-nav-expanded')));
    expect(last.bottom, lessThanOrEqualTo(nav.top));
  });

  testWidgets('route change restores expanded navigation', (tester) async {
    await tester.pumpWidget(app());
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(index: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('biso-nav-expanded')), findsOneWidget);
  });

  testWidgets('accessible navigation stays expanded', (tester) async {
    await tester.pumpWidget(app(accessible: true));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('biso-nav-expanded')), findsOneWidget);
  });

  testWidgets('keyboard hides navigation', (tester) async {
    await tester.pumpWidget(app(keyboard: 300));
    expect(find.byKey(const ValueKey('biso-nav-expanded')), findsNothing);
  });

  testWidgets('horizontal carousel gestures do not minimize navigation', (
    tester,
  ) async {
    await tester.pumpWidget(app(horizontal: true));
    await tester.drag(find.byType(ListView), const Offset(-350, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('biso-nav-expanded')), findsOneWidget);
  });

  testWidgets('expanded tabs navigate; compact tab only expands', (
    tester,
  ) async {
    final selections = <int>[];
    await tester.pumpWidget(app(onSelected: selections.add));
    await tester.tap(find.text('Explore'));
    expect(selections, [1]);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('biso-nav-collapsed')));
    await tester.pumpAndSettle();
    expect(selections, [1]);
  });

  testWidgets(
    'narrow screen and enlarged text fit without animation in reduced motion',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(textScale: 2, reducedMotion: true));
      expect(tester.takeException(), isNull);
      final listBefore = tester.getSize(find.byType(ListView));
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('biso-nav-collapsed')), findsOneWidget);
      expect(tester.getSize(find.byType(ListView)), listBefore);
      expect(tester.takeException(), isNull);
    },
  );
}
