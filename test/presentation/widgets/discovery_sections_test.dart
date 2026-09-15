import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/models/event_model.dart';
import 'package:biso/data/models/webshop_product_model.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/widgets/home/discovery_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [2.0, 3.0]) {
    testWidgets('feed cards fit multi-line content at ${scale}x text', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: PremiumTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    BisoEventCarousel(
                      events: [
                        EventModel(
                          id: 'test',
                          title: 'A full day of student activities on campus',
                          description: '',
                          startDate: DateTime(2026, 9, 14),
                          campusId: '1',
                          location: 'BI Oslo campus',
                        ),
                      ],
                    ),
                    const BisoWebshopCarousel(
                      products: [
                        WebshopProduct(
                          id: 'test',
                          images: [],
                          title: 'BISO student association sweatshirt',
                          regularPrice: 399,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
