import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/models/board_member_model.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/screens/explore/campus_detail_screen.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/leadership/leadership_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/biso_screen_harness.dart';

const _campusId = '1';

final _campus = CampusModel.fromMap({
  '\$id': _campusId,
  'name': 'Oslo',
  'description':
      'The largest BI campus, home to thousands of students across '
      'multiple degree programmes and a very long amount of NOK 1234.50 '
      'worth of student activity.',
  'student_benefits': [
    'Free entry to all BISO events',
    'Access to the student career centre',
    'Discounted gym membership',
    'Mentor programme with alumni',
  ],
  'business_benefits': ['Recruitment access to top students'],
  'career_advantages': ['Internship placements', 'Networking events'],
  'contact_email': 'oslo@biso.no',
  'contact_address': 'Nydalsveien 15, 0484 Oslo',
  'weather': {
    'temperature': 12.4,
    'condition': 'Partly cloudy',
    'icon': '⛅',
    'humidity': 60,
    'wind_speed': 3.2,
  },
  'stats': {
    'active_events': 14,
    'available_jobs': 23,
    'marketplace_items': 5,
    'departments_count': 1234,
  },
});

final _boardMembers = BoardMembersResponse.fromMap({
  'success': true,
  'count': 2,
  'departmentName': 'Ledelsen Oslo',
  'members': [
    {
      'name': 'Kari Nordmann',
      'email': 'kari@biso.no',
      'phone': '+47 99999999',
      'role': 'President',
      'officeLocation': 'A2-102',
    },
    {
      'name': 'Ola Hansen',
      'email': 'ola@biso.no',
      'phone': '',
      'role': 'Vice President',
      'officeLocation': '',
    },
  ],
});

List<Override> _overrides({BoardMembersResponse? boardMembers}) => [
  campusProvider(_campusId).overrideWith((ref) async => _campus),
  boardMembersProvider(
    _campusId,
  ).overrideWith((ref) async => boardMembers ?? _boardMembers),
];

/// A marker screen for a target route, so a navigation test can assert the
/// tap landed on the exact route rather than merely "away from" the campus
/// detail screen.
class _Marker extends StatelessWidget {
  const _Marker(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text(label)));
}

/// Every route `_navigateToExplore` can push, each rendering a distinct
/// marker so a test can tell them apart.
GoRouter _routerFromCampusDetail() => GoRouter(
  initialLocation: '/explore/campus/$_campusId',
  routes: [
    GoRoute(
      path: '/explore/campus/:campusId',
      builder: (context, state) =>
          CampusDetailScreen(campusId: state.pathParameters['campusId']!),
    ),
    GoRoute(
      path: '/explore/events',
      builder: (context, state) => const _Marker('EVENTS_ROUTE'),
    ),
    GoRoute(
      path: '/explore/products',
      builder: (context, state) => const _Marker('PRODUCTS_ROUTE'),
    ),
    GoRoute(
      path: '/explore/volunteer',
      builder: (context, state) => const _Marker('VOLUNTEER_ROUTE'),
    ),
    GoRoute(
      path: '/explore/units',
      builder: (context, state) => const _Marker('UNITS_ROUTE'),
    ),
  ],
);

Future<void> _pumpRouted(WidgetTester tester, GoRouter router) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(),
      child: MaterialApp.router(
        theme: PremiumTheme.build(Brightness.light),
        darkTheme: PremiumTheme.build(Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Campus detail builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const CampusDetailScreen(campusId: _campusId),
      overrides: _overrides(),
      routed: true,
    );
  });

  testWidgets('there is no floating action button', (tester) async {
    await pumpBisoScreen(
      tester,
      const CampusDetailScreen(campusId: _campusId),
      overrides: _overrides(),
      routed: true,
    );
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('the cover starts at y = 0 and the compact title fades in on '
      'scroll', (tester) async {
    await pumpBisoScreen(
      tester,
      const CampusDetailScreen(campusId: _campusId),
      overrides: _overrides(),
      routed: true,
    );
    await tester.pumpAndSettle();

    final cover = tester.getTopLeft(
      find.byKey(const ValueKey('campus-cover')),
    );
    expect(cover.dy, 0);

    final opacityBefore = tester.widget<Opacity>(
      find.ancestor(
        of: find.byKey(const ValueKey('biso-compact-title')),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacityBefore.opacity, 0);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final compactTitle = tester.widget<Text>(
      find.byKey(const ValueKey('biso-compact-title')),
    );
    expect(compactTitle.data, 'Oslo');
    final opacityAfter = tester.widget<Opacity>(
      find.ancestor(
        of: find.byKey(const ValueKey('biso-compact-title')),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacityAfter.opacity, greaterThan(0.9));
  });

  testWidgets('the cover shows the campus name, weather and stats', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const CampusDetailScreen(campusId: _campusId),
      overrides: _overrides(),
      routed: true,
    );
    await tester.pumpAndSettle();

    expect(find.text('Oslo'), findsWidgets);
    expect(find.textContaining('12°'), findsOneWidget);
    expect(find.textContaining('Partly cloudy'), findsOneWidget);
    expect(find.text('1234 Units'), findsOneWidget);
    expect(find.text('14 Events'), findsOneWidget);
    expect(find.text('23 Jobs'), findsOneWidget);
  });

  testWidgets(
    'the department count is never truncated at a large text scale',
    (tester) async {
      await pumpBisoScreen(
        tester,
        const CampusDetailScreen(campusId: _campusId),
        overrides: _overrides(),
        textScale: 1.6,
        routed: true,
      );
      await tester.pumpAndSettle();

      final paragraph = tester.renderObject<RenderParagraph>(
        find.text('1234 Units'),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
    },
  );

  testWidgets('the Event quick action pushes the events route', (
    tester,
  ) async {
    await _pumpRouted(tester, _routerFromCampusDetail());
    await tester.tap(find.text('Event'));
    await tester.pumpAndSettle();

    expect(find.text('EVENTS_ROUTE'), findsOneWidget);
    expect(find.text('PRODUCTS_ROUTE'), findsNothing);
    expect(find.text('VOLUNTEER_ROUTE'), findsNothing);
    expect(find.text('UNITS_ROUTE'), findsNothing);
  });

  testWidgets('the Products quick action pushes the products route', (
    tester,
  ) async {
    await _pumpRouted(tester, _routerFromCampusDetail());
    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();

    expect(find.text('PRODUCTS_ROUTE'), findsOneWidget);
    expect(find.text('EVENTS_ROUTE'), findsNothing);
    expect(find.text('VOLUNTEER_ROUTE'), findsNothing);
    expect(find.text('UNITS_ROUTE'), findsNothing);
  });

  testWidgets('the Jobs quick action pushes the volunteer route', (
    tester,
  ) async {
    await _pumpRouted(tester, _routerFromCampusDetail());
    await tester.tap(find.text('Jobs'));
    await tester.pumpAndSettle();

    expect(find.text('VOLUNTEER_ROUTE'), findsOneWidget);
    expect(find.text('EVENTS_ROUTE'), findsNothing);
    expect(find.text('PRODUCTS_ROUTE'), findsNothing);
    expect(find.text('UNITS_ROUTE'), findsNothing);
  });

  testWidgets('the Units quick action pushes the units route', (
    tester,
  ) async {
    await _pumpRouted(tester, _routerFromCampusDetail());
    await tester.tap(find.text('Units'));
    await tester.pumpAndSettle();

    expect(find.text('UNITS_ROUTE'), findsOneWidget);
    expect(find.text('EVENTS_ROUTE'), findsNothing);
    expect(find.text('PRODUCTS_ROUTE'), findsNothing);
    expect(find.text('VOLUNTEER_ROUTE'), findsNothing);
  });

  testWidgets('benefit cards show benefits and expand for more', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const CampusDetailScreen(campusId: _campusId),
      overrides: _overrides(),
      routed: true,
    );
    await tester.pumpAndSettle();

    expect(find.text('Free entry to all BISO events'), findsOneWidget);
    expect(find.text('Access to the student career centre'), findsOneWidget);
    expect(find.text('Discounted gym membership'), findsOneWidget);
    expect(find.text('Mentor programme with alumni'), findsNothing);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show 1 More'));
    await tester.pumpAndSettle();

    expect(find.text('Mentor programme with alumni'), findsOneWidget);
    expect(find.text('Show Less'), findsOneWidget);
  });

  testWidgets('leadership rows show name and role, and open a detail sheet', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const CampusDetailScreen(campusId: _campusId),
      overrides: _overrides(),
      routed: true,
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Kari Nordmann'),
      find.byType(CustomScrollView),
      const Offset(0, -300),
    );
    expect(find.text('Kari Nordmann'), findsOneWidget);
    expect(find.text('President · A2-102'), findsOneWidget);
    expect(find.text('Ola Hansen'), findsOneWidget);
    expect(find.text('Vice President'), findsOneWidget);

    await tester.tap(find.text('Kari Nordmann'));
    await tester.pumpAndSettle();

    expect(find.text('kari@biso.no'), findsOneWidget);
    expect(find.text('+47 99999999'), findsOneWidget);
  });

  testWidgets('an empty leadership list shows the department-aware message', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const CampusDetailScreen(campusId: _campusId),
      overrides: _overrides(
        boardMembers: BoardMembersResponse.fromMap({
          'success': true,
          'count': 0,
          'departmentName': 'Ledelsen Oslo',
          'members': const [],
        }),
      ),
      routed: true,
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.textContaining('No members found for Ledelsen Oslo'),
      find.byType(CustomScrollView),
      const Offset(0, -300),
    );
    expect(
      find.textContaining('No members found for Ledelsen Oslo'),
      findsOneWidget,
    );
  });

  testWidgets('contact rows show the address and email', (tester) async {
    await pumpBisoScreen(
      tester,
      const CampusDetailScreen(campusId: _campusId),
      overrides: _overrides(),
      routed: true,
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Nydalsveien 15, 0484 Oslo'),
      find.byType(CustomScrollView),
      const Offset(0, -400),
    );
    expect(find.text('Nydalsveien 15, 0484 Oslo'), findsOneWidget);
    expect(find.text('oslo@biso.no'), findsOneWidget);
  });
}
