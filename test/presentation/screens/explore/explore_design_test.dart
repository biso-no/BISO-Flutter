import 'package:biso/data/models/app_config.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/presentation/screens/explore/explore_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/campus/campus_data_provider.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/config/app_config_provider.dart';
import 'package:biso/providers/large_event/large_event_provider.dart';
import 'package:biso/providers/ui/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/biso_screen_harness.dart';

const _campus = CampusModel(
  id: 'oslo',
  name: 'Oslo',
  description: 'Test campus',
  location: 'Oslo',
  imageUrl: '',
  heroImageUrl: '',
  stats: CampusStats(),
);

/// Mirrors the pattern in events_screen_locale_reload_test.dart: the real
/// notifier's async load from SharedPreferences is harmless in tests (it
/// resolves after teardown or leaves the default 'en'), so no stubbing is
/// needed beyond giving each test its own instance.
class _Locale extends LocaleNotifier {}

List<Override> _overrides() => [
  filterCampusProvider.overrideWithValue(_campus),
  campusInitializedProvider.overrideWithValue(true),
  currentCampusDataProvider.overrideWithValue(const AsyncValue.data(null)),
  appConfigProvider.overrideWith((ref) async => const AppConfig()),
  featuredLargeEventProvider.overrideWithValue(null),
  localeProvider.overrideWith((ref) => _Locale()),
];

void main() {
  testWidgets('Explore builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const ExploreScreen(),
      overrides: _overrides(),
    );
  });

  testWidgets('categories are accent-tiled rows and search filters them', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const ExploreScreen(),
      overrides: _overrides(),
    );
    expect(find.byType(BisoIconTile), findsWidgets);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzzz-no-match');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BisoEmptyState), findsOneWidget);
  });

  testWidgets('language action opens a two-option sheet', (tester) async {
    await pumpBisoScreen(
      tester,
      const ExploreScreen(),
      overrides: _overrides(),
    );
    await tester.tap(find.byTooltip('Language'));
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Norsk'), findsOneWidget);
  });
}
