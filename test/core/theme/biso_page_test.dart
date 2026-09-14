import 'package:biso/core/theme/biso_navigation.dart';
import 'package:biso/core/theme/biso_page.dart';
import 'package:biso/core/theme/biso_page_header.dart';
import 'package:biso/core/theme/premium_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const tabs = [
  BisoNavDestination(icon: CupertinoIcons.house, label: 'Home'),
  BisoNavDestination(icon: CupertinoIcons.square_grid_2x2, label: 'Explore'),
  BisoNavDestination(icon: CupertinoIcons.person, label: 'Profile'),
];

List<Widget> rows() => [
  SliverList.builder(
    itemCount: 40,
    itemBuilder: (_, i) =>
        SizedBox(height: 64, child: Text('Row $i', key: ValueKey('row-$i'))),
  ),
];

Widget app(
  Widget page, {
  bool shell = false,
  double keyboard = 0,
  double textScale = 1,
}) {
  return MaterialApp(
    theme: PremiumTheme.build(Brightness.light),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(top: 47, bottom: 34),
          viewPadding: const EdgeInsets.only(top: 47, bottom: 34),
          viewInsets: EdgeInsets.only(bottom: keyboard),
          textScaler: TextScaler.linear(textScale),
        ),
        child: shell
            ? BisoNavigationScaffold(
                currentIndex: 0,
                routeKey: 'test',
                destinations: tabs,
                onSelected: (_) {},
                child: page,
              )
            : page,
      ),
    ),
  );
}

void phone(WidgetTester tester, [Size size = const Size(390, 844)]) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Finder get headerFinder => find.byKey(const ValueKey('biso-page-header'));

Finder get scrollable => find
    .descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    )
    .first;

bool anyRowUnder(WidgetTester tester, Rect area) => List.generate(
  40,
  (i) => find.byKey(ValueKey('row-$i')),
).where((f) => f.evaluate().isNotEmpty).any(
  (f) => tester.getRect(f).overlaps(area),
);

void main() {
  testWidgets('large title and first row start below the header', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(app(BisoPage(title: 'Shop', slivers: rows())));
    await tester.pump();
    final header = tester.getRect(headerFinder);
    final title = tester.getRect(find.byKey(const ValueKey('biso-large-title')));
    expect(header.height, 47 + kBisoHeaderHeight);
    expect(title.top, greaterThanOrEqualTo(header.bottom));
    expect(
      tester.getRect(find.byKey(const ValueKey('row-0'))).top,
      greaterThanOrEqualTo(title.bottom),
    );
    expect(find.byKey(const ValueKey('biso-header-band')), findsNothing);
  });

  testWidgets('scrolling moves rows under a blurred header with a title', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(app(BisoPage(title: 'Shop', slivers: rows())));
    await tester.pump();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(anyRowUnder(tester, tester.getRect(headerFinder)), isTrue);
    final compact = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('biso-compact-title')),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(compact.opacity, 1);
  });

  testWidgets('over-image pages start content at the top edge', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      app(BisoPage(title: 'Hoodie', overImage: true, slivers: rows())),
    );
    await tester.pump();
    expect(tester.getRect(find.byKey(const ValueKey('row-0'))).top, 0);
    expect(find.byKey(const ValueKey('biso-large-title')), findsNothing);
  });

  testWidgets('last row clears the bottom bar, which clears the tab bar', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      app(
        BisoPage(
          title: 'Cart',
          slivers: rows(),
          bottomBar: const SizedBox(
            key: ValueKey('bar'),
            height: 72,
            child: ColoredBox(color: Colors.black),
          ),
        ),
        shell: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -6000));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('biso-nav-collapsed')));
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(scrollable).position.extentAfter, 0);
    final bar = tester.getRect(find.byKey(const ValueKey('bar')));
    final nav = tester.getRect(find.byKey(const ValueKey('biso-nav-expanded')));
    expect(
      tester.getRect(find.byKey(const ValueKey('row-39'))).bottom,
      lessThanOrEqualTo(bar.top),
    );
    expect(bar.bottom, lessThanOrEqualTo(nav.top));
  });

  testWidgets('the keyboard drops the bottom bar to the keyboard edge', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      app(
        BisoPage(
          title: 'Chat',
          largeTitle: false,
          slivers: rows(),
          bottomBar: const SizedBox(key: ValueKey('bar'), height: 56),
        ),
        shell: true,
        keyboard: 300,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey('bar'))).bottom,
      closeTo(844 - 300, 0.5),
    );
  });

  testWidgets('pull to refresh starts below the header', (tester) async {
    phone(tester);
    var refreshed = false;
    await tester.pumpWidget(
      app(
        BisoPage(
          title: 'Orders',
          slivers: rows(),
          onRefresh: () async => refreshed = true,
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).edgeOffset,
      47 + kBisoHeaderHeight,
    );
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 400),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(refreshed, isTrue);
  });

  testWidgets('body pages receive the same insets and drive the header', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      app(
        BisoPage(
          title: 'Scanner',
          body: Builder(
            builder: (context) => ListView(
              padding: BisoPageInsets.padding(context),
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(
                    height: 64,
                    child: Text('Row $i', key: ValueKey('row-$i')),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.getRect(find.byKey(const ValueKey('row-0'))).top,
      greaterThanOrEqualTo(tester.getRect(headerFinder).bottom),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('biso-header-band')), findsOneWidget);
  });

  testWidgets('nested scroll views drive the header at their depth', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      app(
        BisoPage(
          title: 'Onboarding',
          notificationDepth: 1,
          body: PageView(
            children: [
              Builder(
                builder: (context) => ListView(
                  padding: BisoPageInsets.padding(context),
                  children: [
                    for (var i = 0; i < 40; i++)
                      SizedBox(height: 64, child: Text('Row $i')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('biso-header-band')), findsOneWidget);
  });

  testWidgets('back button appears only when the route can pop', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(app(BisoPage(title: 'Shop', slivers: rows())));
    expect(find.byTooltip('Back'), findsNothing);
    Navigator.of(tester.element(find.byType(BisoPage))).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            const BisoPage(title: 'Detail', largeTitle: false, slivers: []),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsOneWidget);
  });

  testWidgets('large text on a narrow phone does not overflow', (tester) async {
    phone(tester, const Size(320, 720));
    await tester.pumpWidget(
      app(
        BisoPage(
          title: 'Reimbursements and expenses',
          actions: [
            BisoHeaderAction(
              icon: CupertinoIcons.plus,
              tooltip: 'New',
              onPressed: () {},
            ),
          ],
          slivers: rows(),
        ),
        textScale: 2,
      ),
    );
    await tester.pump();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('debug initial scroll pre-scrolls the next page', (tester) async {
    phone(tester);
    BisoPageDebug.initialScroll.value = 300;
    addTearDown(() => BisoPageDebug.initialScroll.value = 0);
    await tester.pumpWidget(app(BisoPage(title: 'Shop', slivers: rows())));
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      300,
    );
    expect(find.byKey(const ValueKey('biso-header-band')), findsOneWidget);
  });
}
