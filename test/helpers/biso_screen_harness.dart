import 'package:biso/core/theme/biso_navigation.dart';
import 'package:biso/core/theme/biso_page.dart';
import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _tabs = [
  BisoNavDestination(icon: CupertinoIcons.house, label: 'Home'),
  BisoNavDestination(icon: CupertinoIcons.square_grid_2x2, label: 'Explore'),
  BisoNavDestination(icon: CupertinoIcons.person_crop_circle, label: 'Profile'),
];

/// Pumps [screen] the way the app shows it: themed and localized, on a
/// 390x844 phone with a notch and home indicator, inside the tab shell.
/// Set [routed] for screens that read GoRouterState during build.
Future<void> pumpBisoScreen(
  WidgetTester tester,
  Widget screen, {
  List<Override> overrides = const [],
  Brightness brightness = Brightness.light,
  double textScale = 1,
  bool inShell = true,
  bool routed = false,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  Widget framed(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      padding: const EdgeInsets.only(top: 47, bottom: 34),
      viewPadding: const EdgeInsets.only(top: 47, bottom: 34),
      textScaler: TextScaler.linear(textScale),
    ),
    child: inShell
        ? BisoNavigationScaffold(
            currentIndex: 1,
            routeKey: 'test',
            destinations: _tabs,
            onSelected: (_) {},
            child: screen,
          )
        : screen,
  );

  final themeMode = brightness == Brightness.dark
      ? ThemeMode.dark
      : ThemeMode.light;
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: routed
          ? MaterialApp.router(
              theme: PremiumTheme.build(Brightness.light),
              darkTheme: PremiumTheme.build(Brightness.dark),
              themeMode: themeMode,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: GoRouter(
                routes: [
                  GoRoute(path: '/', builder: (context, _) => framed(context)),
                ],
              ),
            )
          : MaterialApp(
              theme: PremiumTheme.build(Brightness.light),
              darkTheme: PremiumTheme.build(Brightness.dark),
              themeMode: themeMode,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Builder(builder: framed),
            ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Pumps the screen in light and dark, at normal and enlarged text, and fails
/// on any layout exception or if the screen is not built on BisoPage.
Future<void> expectBuildsCleanly(
  WidgetTester tester,
  Widget Function() screen, {
  List<Override> overrides = const [],
  bool inShell = true,
  bool routed = false,
}) async {
  for (final brightness in Brightness.values) {
    for (final textScale in [1.0, 1.6]) {
      await pumpBisoScreen(
        tester,
        screen(),
        overrides: overrides,
        brightness: brightness,
        textScale: textScale,
        inShell: inShell,
        routed: routed,
      );
      expect(
        tester.takeException(),
        isNull,
        reason: '$brightness at text scale $textScale',
      );
      expect(find.byType(BisoPage), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    }
  }
}
