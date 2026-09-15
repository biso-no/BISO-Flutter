import 'package:biso/core/theme/biso_navigation.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/presentation/screens/home/premium_home_screen.dart';
import 'package:biso/providers/auth/auth_provider.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/large_event/large_event_provider.dart';
import 'package:biso/providers/notification/notification_provider.dart';
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

/// A campus that is never "ready" (`campusInitializedProvider` stays false),
/// so the screen's private `_latest*Provider`s — which read `AppwriteService`
/// directly and cannot be overridden from outside the screen file — are never
/// watched and the content sections render their loading skeleton instead of
/// making a real network call.
class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth() : super(const AuthState());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> _overrides({int unread = 0}) => [
  filterCampusProvider.overrideWithValue(_campus),
  campusInitializedProvider.overrideWithValue(false),
  heroShowcaseItemsProvider.overrideWithValue(const []),
  unreadCountProvider.overrideWithValue(unread),
  authStateProvider.overrideWith((_) => _Auth()),
];

void main() {
  testWidgets('Home builds on BisoPage in every appearance', (tester) async {
    await expectBuildsCleanly(
      tester,
      () => PremiumHomePage(navigateToTab: (_) {}),
      overrides: _overrides(),
      routed: true,
    );
  });

  testWidgets('home header carries notifications with the unread badge', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      PremiumHomePage(navigateToTab: (_) {}),
      routed: true,
      overrides: _overrides(unread: 4),
    );
    expect(find.byTooltip('Notifications'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('campus switcher keeps the last campus clear of the tab bar', (
    tester,
  ) async {
    CampusModel campus(String name) => CampusModel(
      id: name.toLowerCase(),
      name: name,
      description: '',
      location: name,
      imageUrl: '',
      heroImageUrl: '',
      stats: const CampusStats(),
    );

    await pumpBisoScreen(
      tester,
      // Mirrors the app's ShellRoute: the page, and the sheets it opens, live
      // in a navigator beneath the floating tab bar.
      Navigator(
        onGenerateRoute: (_) => MaterialPageRoute(
          builder: (_) => PremiumHomePage(navigateToTab: (_) {}),
        ),
      ),
      routed: true,
      overrides: [
        ..._overrides(),
        switcherCampusesProvider.overrideWith(
          (_) async => [
            for (final name in [
              'Oslo',
              'Bergen',
              'Trondheim',
              'Stavanger',
              'National',
            ])
              campus(name),
          ],
        ),
      ],
    );

    await tester.tap(find.widgetWithText(TextButton, 'Oslo'));
    await tester.pumpAndSettle();

    final barTop = tester.getTopLeft(find.byType(BisoNavigationBar)).dy;
    expect(tester.getBottomLeft(find.text('National')).dy, lessThan(barTop));
  });
}
