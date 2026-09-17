import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/models/app_config.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/screens/explore/explore_screen.dart';
import 'package:biso/presentation/screens/scanner/scanner_route.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/campus/campus_data_provider.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/config/app_config_provider.dart';
import 'package:biso/providers/large_event/large_event_provider.dart';
import 'package:biso/providers/member_pass/scanner_access_provider.dart';
import 'package:biso/providers/ui/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fake_member_pass_api.dart';

const _campus = CampusModel(
  id: 'oslo',
  name: 'Oslo',
  description: 'Test campus',
  location: 'Oslo',
  imageUrl: '',
  heroImageUrl: '',
  stats: CampusStats(),
);

class _Locale extends LocaleNotifier {}

void main() {
  late FixedScannerAccess access;

  Future<void> pump(WidgetTester tester, ScannerAccessState? state) async {
    access = FixedScannerAccess(state);
    final router = GoRouter(
      initialLocation: '/explore',
      routes: [
        GoRoute(path: '/explore', builder: (_, _) => const ExploreScreen()),
        GoRoute(
          path: membershipScannerPath,
          builder: (_, _) => const Scaffold(body: Text('Scanner')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          filterCampusProvider.overrideWithValue(_campus),
          campusInitializedProvider.overrideWithValue(true),
          currentCampusDataProvider.overrideWithValue(
            const AsyncValue.data(null),
          ),
          appConfigProvider.overrideWith((ref) async => const AppConfig()),
          featuredLargeEventProvider.overrideWithValue(null),
          localeProvider.overrideWith((ref) => _Locale()),
          scannerAccessProvider.overrideWith(() => access),
        ],
        child: MaterialApp.router(
          theme: PremiumTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('scanners see the tile first', (tester) async {
    await pump(tester, grantedAccess);
    final titles = tester
        .widgetList<BisoListRow>(find.byType(BisoListRow))
        .map((row) => row.title)
        .toList();
    expect(titles.first, 'Scan memberships');
    expect(find.text('Check member passes at the door'), findsOneWidget);
  });

  testWidgets('the tile opens the scanner', (tester) async {
    await pump(tester, grantedAccess);
    await tester.tap(find.text('Scan memberships'));
    await tester.pumpAndSettle();
    expect(find.text('Scanner'), findsOneWidget);
  });

  testWidgets('everyone else never sees it', (tester) async {
    await pump(tester, const ScannerDenied());
    expect(find.text('Scan memberships'), findsNothing);
  });

  testWidgets('it stays hidden while access is being checked', (tester) async {
    await pump(tester, null);
    expect(find.text('Scan memberships'), findsNothing);
  });

  testWidgets('opening Explore asks whether access is still fresh', (
    tester,
  ) async {
    await pump(tester, const ScannerDenied());
    expect(access.freshCalls, 1);
  });
}
