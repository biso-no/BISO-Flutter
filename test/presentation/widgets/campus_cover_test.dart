import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/widgets/dynamic_hero_carousel.dart';
import 'package:biso/providers/notification/notification_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'campus cover fits narrow screen at 2x text in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var campusTaps = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [unreadCountProvider.overrideWithValue(0)],
            child: MaterialApp(
              theme: dark ? PremiumTheme.darkTheme : PremiumTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('no'),
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: DynamicHeroCarousel(
                      campus: CampusModel.fromMap({
                        'id': '3',
                        'name': 'Trondheim',
                      }),
                      showcaseItems: const [],
                      onCampusTap: () => campusTaps++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.widgetWithText(TextButton, 'Trondheim'));
        expect(campusTaps, 1);
      },
    );
  }
}
