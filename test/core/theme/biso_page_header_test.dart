import 'package:biso/core/theme/biso_chrome.dart';
import 'package:biso/core/theme/biso_colors.dart';
import 'package:biso/core/theme/biso_page_header.dart';
import 'package:biso/core/theme/premium_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget header({
  ValueNotifier<double>? offset,
  double titleExtent = 60,
  bool showLargeTitle = true,
  bool overImage = false,
  bool reducedMotion = false,
  bool highContrast = false,
  List<BisoHeaderAction> actions = const [],
  BisoHeaderSearch? search,
  Widget? leading,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) {
  return MaterialApp(
    theme: PremiumTheme.build(brightness),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(top: 47),
          disableAnimations: reducedMotion,
          highContrast: highContrast,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: BisoPageHeader(
              offset: offset ?? ValueNotifier(0),
              largeTitleExtent: ValueNotifier(titleExtent),
              title: 'Shop',
              showLargeTitle: showLargeTitle,
              overImage: overImage,
              actions: actions,
              search: search,
              leading: leading,
            ),
          ),
        ),
      ),
    ),
  );
}

double titleOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('biso-compact-title')),
            matching: find.byType(Opacity),
          )
          .first,
    )
    .opacity;

double? scrimOpacity(WidgetTester tester) {
  final finder = find.byKey(const ValueKey('biso-header-image-scrim'));
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<Opacity>(finder).opacity;
}

double scrimTopAlpha(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(
      of: find.byKey(const ValueKey('biso-header-image-scrim')),
      matching: find.byType(DecoratedBox),
    ),
  );
  final gradient = (box.decoration as BoxDecoration).gradient as LinearGradient;
  return gradient.colors.first.a;
}

/// Every capsule's [BisoChrome], with its `Element` so a matching fallback
/// `DecoratedBox` can be found underneath it.
List<Element> chromeElements(WidgetTester tester) =>
    tester.elementList(find.byType(BisoChrome)).toList();

/// The fallback (non-native / high-contrast) surface color painted behind
/// one [BisoChrome] — the path the test platform always takes.
Color chromeFallbackColor(WidgetTester tester, Element chrome) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byElementPredicate((e) => e == chrome),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return (box.decoration as BoxDecoration).color!;
}

double bandTintAlpha(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byKey(const ValueKey('biso-header-band')),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return (box.decoration as BoxDecoration).color!.a;
}

final favorite = BisoHeaderAction(
  icon: CupertinoIcons.heart,
  tooltip: 'Favorite',
  onPressed: () {},
);

void main() {
  testWidgets('at rest there is no band, no blur and no compact title', (
    tester,
  ) async {
    await tester.pumpWidget(header());
    expect(find.byKey(const ValueKey('biso-header-band')), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(titleOpacity(tester), 0);
    expect(
      tester.getSize(find.byKey(const ValueKey('biso-page-header'))).height,
      47 + kBisoHeaderHeight,
    );
  });

  testWidgets('band fades in over 12 pt; title follows the large title', (
    tester,
  ) async {
    final offset = ValueNotifier<double>(0);
    await tester.pumpWidget(header(offset: offset));
    offset.value = 6;
    await tester.pump();
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(bandTintAlpha(tester), closeTo(0.78 * 0.5, 0.001));
    expect(titleOpacity(tester), 0);
    offset.value = 42; // extent 60 - 12 - 12 = 36, so (42 - 36) / 12 = 0.5
    await tester.pump();
    expect(titleOpacity(tester), closeTo(0.5, 0.001));
    offset.value = 200;
    await tester.pump();
    expect(bandTintAlpha(tester), closeTo(0.78, 0.001));
    expect(titleOpacity(tester), 1);
  });

  testWidgets(
    'compact title is as full as the band once the large title text is under '
    'the header, and never fuller than the band',
    (tester) async {
      for (final extent in [60.0, 30.0, 16.0]) {
        final offset = ValueNotifier<double>(0);
        await tester.pumpWidget(header(offset: offset, titleExtent: extent));
        // BisoLargeTitle pads its text 12 pt below, so the text is entirely
        // under the header from extent - 12.
        for (var at = 0.0; at <= extent + 24; at += 1) {
          offset.value = at;
          await tester.pump();
          final title = titleOpacity(tester);
          final band = find.byKey(const ValueKey('biso-header-band'));
          final bandAmount = band.evaluate().isEmpty
              ? 0.0
              : bandTintAlpha(tester) / 0.78;
          if (at >= extent - 12) {
            // As full as the band allows (the band itself is full from 12).
            expect(
              title,
              closeTo(bandAmount, 0.001),
              reason: 'extent $extent, offset $at',
            );
          }
          expect(
            title,
            lessThanOrEqualTo(bandAmount + 0.001),
            reason: 'extent $extent, offset $at: title without its band',
          );
        }
      }
    },
  );

  testWidgets('dark mode tints the band with 72% paper', (tester) async {
    await tester.pumpWidget(
      header(offset: ValueNotifier(200), brightness: Brightness.dark),
    );
    expect(bandTintAlpha(tester), closeTo(0.72, 0.001));
  });

  testWidgets('reduced motion switches the band and title without fading', (
    tester,
  ) async {
    final offset = ValueNotifier<double>(1);
    await tester.pumpWidget(header(offset: offset, reducedMotion: true));
    expect(bandTintAlpha(tester), closeTo(0.78, 0.001));
    expect(titleOpacity(tester), 0);
    offset.value = 53;
    await tester.pump();
    expect(titleOpacity(tester), 1);
  });

  testWidgets('high contrast makes the band opaque without blur', (
    tester,
  ) async {
    await tester.pumpWidget(
      header(offset: ValueNotifier(200), highContrast: true),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    expect(bandTintAlpha(tester), 1);
  });

  testWidgets('detail pages show the compact title immediately', (
    tester,
  ) async {
    await tester.pumpWidget(header(showLargeTitle: false));
    expect(titleOpacity(tester), 1);
  });

  testWidgets('over an image the header starts clear with light content', (
    tester,
  ) async {
    final offset = ValueNotifier<double>(0);
    await tester.pumpWidget(
      header(offset: offset, overImage: true, actions: [favorite]),
    );
    SystemUiOverlayStyle style() => tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.descendant(
            of: find.byType(BisoPageHeader),
            matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          ),
        )
        .value;
    expect(tester.widget<Icon>(find.byIcon(CupertinoIcons.heart)).color,
        Colors.white);
    expect(titleOpacity(tester), 0);
    expect(style(), SystemUiOverlayStyle.light);
    offset.value = 200;
    await tester.pump();
    expect(tester.widget<Icon>(find.byIcon(CupertinoIcons.heart)).color,
        BisoPalette.light.ink);
    expect(titleOpacity(tester), 1);
    expect(style(), SystemUiOverlayStyle.dark);
  });

  testWidgets(
    'overImage at rest draws a top scrim so controls stay legible',
    (tester) async {
      await tester.pumpWidget(
        header(overImage: true, offset: ValueNotifier(0)),
      );
      expect(
        find.byKey(const ValueKey('biso-header-image-scrim')),
        findsOneWidget,
      );
      expect(find.byType(BackdropFilter), findsNothing);
      expect(scrimOpacity(tester), 1);
      expect(scrimTopAlpha(tester), closeTo(0.35, 0.001));
    },
  );

  testWidgets(
    'overImage once the band is fully in, the scrim has faded out',
    (tester) async {
      await tester.pumpWidget(
        header(overImage: true, offset: ValueNotifier(200)),
      );
      final opacity = scrimOpacity(tester);
      expect(opacity == null || opacity == 0, isTrue);
    },
  );

  testWidgets('not overImage never draws the scrim', (tester) async {
    await tester.pumpWidget(header(offset: ValueNotifier(0)));
    expect(find.byKey(const ValueKey('biso-header-image-scrim')), findsNothing);
    await tester.pumpWidget(header(offset: ValueNotifier(200)));
    expect(find.byKey(const ValueKey('biso-header-image-scrim')), findsNothing);
  });

  testWidgets(
    'overImage at offset 0 every capsule darkens itself for legibility',
    (tester) async {
      await tester.pumpWidget(
        header(
          overImage: true,
          offset: ValueNotifier(0),
          leading: const BisoBackButton(),
          actions: [favorite],
        ),
      );

      final chromes = chromeElements(tester);
      // Leading (back button) and trailing (favorite action) capsules.
      expect(chromes.length, 2);
      for (final chrome in chromes) {
        expect((chrome.widget as BisoChrome).onImage, isTrue);
        final color = chromeFallbackColor(tester, chrome);
        expect(color.r, 0);
        expect(color.g, 0);
        expect(color.b, 0);
        expect(color.a, closeTo(0.35, 0.01));
      }
    },
  );

  testWidgets(
    'once the band is fully in, or when not overImage, capsules use the '
    'ordinary surface fallback',
    (tester) async {
      final scheme = PremiumTheme.build(Brightness.light).colorScheme;

      await tester.pumpWidget(
        header(
          overImage: true,
          offset: ValueNotifier(200),
          leading: const BisoBackButton(),
          actions: [favorite],
        ),
      );
      var chromes = chromeElements(tester);
      expect(chromes.length, 2);
      for (final chrome in chromes) {
        expect((chrome.widget as BisoChrome).onImage, isFalse);
        expect(chromeFallbackColor(tester, chrome), scheme.surface);
      }

      await tester.pumpWidget(
        header(
          offset: ValueNotifier(0),
          leading: const BisoBackButton(),
          actions: [favorite],
        ),
      );
      chromes = chromeElements(tester);
      expect(chromes.length, 2);
      for (final chrome in chromes) {
        expect((chrome.widget as BisoChrome).onImage, isFalse);
        expect(chromeFallbackColor(tester, chrome), scheme.surface);
      }
    },
  );

  testWidgets('actions and search share one glass capsule', (tester) async {
    await tester.pumpWidget(
      header(
        actions: [favorite],
        search: BisoHeaderSearch(hintText: 'Search shop', onChanged: (_) {}),
      ),
    );
    expect(find.byType(BisoChrome), findsOneWidget);
    expect(find.byTooltip('Favorite'), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);
  });

  testWidgets('action badges show their count', (tester) async {
    await tester.pumpWidget(
      header(
        actions: [
          BisoHeaderAction(
            icon: CupertinoIcons.bag,
            tooltip: 'Cart',
            onPressed: () {},
            badge: 3,
          ),
        ],
      ),
    );
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('search expands in place, debounces, and closing clears', (
    tester,
  ) async {
    final queries = <String>[];
    await tester.pumpWidget(
      header(
        search: BisoHeaderSearch(
          hintText: 'Search shop',
          onChanged: queries.add,
        ),
      ),
    );
    final headerRect = tester.getRect(
      find.byKey(const ValueKey('biso-page-header')),
    );
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('biso-header-search')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('biso-page-header'))),
      headerRect,
    );
    final field = find.byType(TextField);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    await tester.enterText(field, 'hoodie');
    await tester.pump(const Duration(milliseconds: 400));
    expect(queries, ['hoodie']);
    await tester.enterText(field, 'cap');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    expect(queries, ['hoodie', '']);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Recent searches'), findsNothing);
  });

  testWidgets('an initial query starts with search open', (tester) async {
    await tester.pumpWidget(
      header(
        search: BisoHeaderSearch(
          hintText: 'Search shop',
          initialQuery: 'hoodie',
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'hoodie'), findsOneWidget);
  });

  testWidgets('back button is a labelled glass button', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      header(leading: BisoBackButton(onPressed: () => tapped = true)),
    );
    await tester.tap(find.byTooltip('Back'));
    expect(tapped, isTrue);
  });

  testWidgets('narrow screen with large text fits, searching or not', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      header(
        textScale: 2,
        leading: const BisoBackButton(),
        actions: [favorite],
        search: BisoHeaderSearch(hintText: 'Search shop', onChanged: (_) {}),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
