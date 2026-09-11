import 'package:biso/core/theme/biso_colors.dart';
import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/presentation/widgets/biso/biso_icon_tile.dart';
import 'package:biso/presentation/widgets/biso/biso_list.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {double textScale = 1}) => MaterialApp(
  theme: PremiumTheme.build(Brightness.light),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: child),
    ),
  ),
);

void main() {
  testWidgets('icon tiles use the accent fill and glyph', (tester) async {
    await tester.pumpWidget(
      app(
        const Column(
          children: [
            BisoIconTile(icon: CupertinoIcons.calendar, accent: BisoAccent.blue),
            BisoIconTile(icon: CupertinoIcons.gear),
          ],
        ),
      ),
    );
    final boxes = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(BisoIconTile),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((b) => (b.decoration as BoxDecoration).color)
        .toList();
    expect(boxes, [
      BisoAccent.blue.fixedFill,
      BisoPalette.light.surfaceRaised,
    ]);
    expect(
      tester.widget<Icon>(find.byIcon(CupertinoIcons.calendar)).color,
      BisoAccent.blue.fixedGlyph,
    );
    expect(
      tester.getSize(find.byType(BisoIconTile).first),
      const Size(32, 32),
    );
  });

  testWidgets('rows show a chevron only when tappable without trailing', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      app(
        BisoListGroup(
          children: [
            BisoListRow(title: 'Orders', onTap: () => taps++),
            BisoListRow(
              title: 'Dark mode',
              trailing: Switch.adaptive(value: true, onChanged: (_) {}),
              onTap: () {},
            ),
            const BisoListRow(title: 'Email', value: 'student@bi.no'),
          ],
        ),
      ),
    );
    expect(find.byIcon(CupertinoIcons.chevron_forward), findsOneWidget);
    await tester.tap(find.text('Orders'));
    expect(taps, 1);
    expect(
      tester.getSize(find.byType(BisoListRow).first).height,
      greaterThanOrEqualTo(56),
    );
  });

  testWidgets('groups separate rows with inset hairlines', (tester) async {
    await tester.pumpWidget(
      app(
        const BisoListGroup(
          dividerIndent: 16,
          children: [
            BisoListRow(title: 'A'),
            BisoListRow(title: 'B'),
            BisoListRow(title: 'C'),
          ],
        ),
      ),
    );
    expect(find.byType(BisoRowDivider), findsNWidgets(2));
    expect(
      tester.widget<BisoRowDivider>(find.byType(BisoRowDivider).first).indent,
      16,
    );
  });

  testWidgets('a row reads as one semantic node with its value', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      app(const BisoListRow(title: 'Language', value: 'English')),
    );
    expect(find.bySemanticsLabel(RegExp('Language.*English', dotAll: true)),
        findsOneWidget);
    semantics.dispose();
  });

  testWidgets('sections title their content and can carry an action', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        BisoSection(
          title: 'Favorites',
          action: TextButton(onPressed: () {}, child: const Text('See all')),
          footer: 'Pinned items',
          child: const BisoListGroup(children: [BisoListRow(title: 'A')]),
        ),
      ),
    );
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
    expect(find.text('Pinned items'), findsOneWidget);
  });

  testWidgets('sliver groups build lazily', (tester) async {
    await tester.pumpWidget(
      app(
        CustomScrollView(
          slivers: [
            SliverBisoListGroup(
              itemCount: 1000,
              itemBuilder: (_, i) => BisoListRow(title: 'Row $i'),
            ),
          ],
        ),
      ),
    );
    expect(find.byType(BisoListRow).evaluate().length, lessThan(40));
    expect(find.byType(BisoRowDivider), findsWidgets);
  });

  testWidgets('long text at large scale on a narrow screen fits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        BisoListGroup(
          children: [
            BisoListRow(
              leading: const BisoIconTile(icon: CupertinoIcons.bag),
              title: 'A very long localized row title that wraps',
              subtitle: 'And a subtitle that is also rather long',
              value: 'NOK 1 299',
              onTap: () {},
            ),
          ],
        ),
        textScale: 2,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
