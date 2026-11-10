import 'dart:async';

import 'package:biso/data/models/app_config.dart';
import 'package:biso/data/models/campus_benefit.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/services/benefits_api_client.dart';
import 'package:biso/presentation/screens/explore/explore_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/benefits/benefits_providers.dart';
import 'package:biso/providers/campus/campus_data_provider.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/config/app_config_provider.dart';
import 'package:biso/providers/large_event/large_event_provider.dart';
import 'package:biso/providers/member_pass/scanner_access_provider.dart';
import 'package:biso/providers/ui/locale_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/biso_screen_harness.dart';
import '../../../helpers/fake_member_pass_api.dart';

const _trondheim = CampusModel(
  id: '3',
  name: 'Trondheim',
  description: 'Test campus',
  location: 'Trondheim',
  imageUrl: '',
  heroImageUrl: '',
  stats: CampusStats(),
);

class _Locale extends LocaleNotifier {}

final _benefitsStub = GoRoute(
  path: '/explore/benefits',
  builder: (_, state) => Scaffold(body: Text('benefits ${state.uri}')),
);

Future<void> _pump(
  WidgetTester tester, {
  required Future<List<CampusBenefit>> Function() load,
  ScannerAccessState? scanner = const ScannerDenied(),
}) => pumpBisoScreen(
  tester,
  const ExploreScreen(),
  routed: true,
  locale: const Locale('no'),
  extraRoutes: [_benefitsStub],
  overrides: [
    filterCampusProvider.overrideWithValue(_trondheim),
    campusInitializedProvider.overrideWithValue(true),
    currentCampusDataProvider.overrideWithValue(const AsyncValue.data(null)),
    appConfigProvider.overrideWith((ref) async => const AppConfig()),
    featuredLargeEventProvider.overrideWithValue(null),
    localeProvider.overrideWith((ref) => _Locale()),
    scannerAccessProvider.overrideWith(() => FixedScannerAccess(scanner)),
    campusBenefitsProvider('3').overrideWith((_) => load()),
  ],
);

List<String> _titles(WidgetTester tester) => tester
    .widgetList<BisoListRow>(find.byType(BisoListRow))
    .map((row) => row.title)
    .toList();

BisoListRow _benefitsRow(WidgetTester tester) => tester.widget<BisoListRow>(
  find.widgetWithText(BisoListRow, 'Medlemsfordeler'),
);

const _notDeployed = BenefitsApiException(
  BenefitsApiErrorKind.notDeployed,
  statusCode: 404,
);

void main() {
  testWidgets(
    'Explore lists "Medlemsfordeler" first and it opens /explore/benefits',
    (tester) async {
      // Even above the scanner tile, for those who have it.
      await _pump(tester, load: () async => const [], scanner: grantedAccess);
      expect(_titles(tester).take(2), ['Medlemsfordeler', 'Skann medlemskap']);
      final row = _benefitsRow(tester);
      expect(row.subtitle, 'Rabatter og tilbud for medlemmer');
      final tile = row.leading! as BisoIconTile;
      expect(tile.icon, CupertinoIcons.gift);
      expect(tile.accent, BisoAccent.gold);

      await tester.tap(find.text('Medlemsfordeler'));
      await tester.pumpAndSettle();
      expect(find.text('benefits /explore/benefits'), findsOneWidget);
    },
  );

  testWidgets('it shows while the list loads', (tester) async {
    await _pump(tester, load: () => Completer<List<CampusBenefit>>().future);
    expect(_titles(tester).first, 'Medlemsfordeler');
  });

  testWidgets('it shows after an error other than notDeployed', (tester) async {
    await _pump(
      tester,
      load: () async =>
          throw const BenefitsApiException(BenefitsApiErrorKind.network),
    );
    expect(_titles(tester).first, 'Medlemsfordeler');
  });

  testWidgets('Explore search "fordel" finds it, and so does "medlem"', (
    tester,
  ) async {
    await _pump(tester, load: () async => const []);
    final label = MaterialLocalizations.of(
      tester.element(find.byType(ExploreScreen)),
    ).searchFieldLabel;
    await tester.tap(find.byTooltip(label));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'fordel');
    await tester.pump(const Duration(milliseconds: 400));
    expect(_titles(tester), ['Medlemsfordeler']);

    await tester.enterText(find.byType(TextField), 'medlem');
    await tester.pump(const Duration(milliseconds: 400));
    expect(_titles(tester), contains('Medlemsfordeler'));
  });

  testWidgets('hidden on notDeployed', (tester) async {
    await _pump(tester, load: () async => throw _notDeployed);
    expect(find.text('Medlemsfordeler'), findsNothing);
    expect(_titles(tester).first, 'Arrangementer');
  });
}
