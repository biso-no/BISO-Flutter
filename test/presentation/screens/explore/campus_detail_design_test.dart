import 'dart:async';

import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/models/board_member_model.dart';
import 'package:biso/data/models/campus_benefit.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/services/benefits_api_client.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/screens/explore/campus_detail_screen.dart';
import 'package:biso/presentation/widgets/biso/biso.dart'
    show BisoErrorState, BisoSkeleton;
import 'package:biso/providers/benefits/benefits_providers.dart';
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

CampusBenefit _benefit(
  String id,
  BenefitSection section,
  String nb, {
  String? en,
}) => CampusBenefit(
  id: id,
  campusId: _campusId,
  section: section,
  title: BenefitText(nb: nb, en: en),
  redemptionType: BenefitRedemptionType.none,
);

final _benefits = <CampusBenefit>[
  _benefit('m1', BenefitSection.member, 'Gratis inngang', en: 'Free entry'),
  _benefit('m2', BenefitSection.member, 'Treningsrabatt', en: 'Gym discount'),
  _benefit('m3', BenefitSection.member, 'Kaffe-rabatt', en: 'Coffee discount'),
  _benefit(
    'm4',
    BenefitSection.member,
    'Mentorprogram',
    en: 'Mentor programme',
  ),
  _benefit('m5', BenefitSection.member, 'Bokrabatt', en: 'Book discount'),
  _benefit('c1', BenefitSection.career, 'Praksisplasser', en: 'Internships'),
  _benefit('s1', BenefitSection.social, 'Fadderuke', en: 'Welcome week'),
  _benefit('f1', BenefitSection.safety, 'Studentpresten', en: 'Student priest'),
  _benefit('b1', BenefitSection.business, 'Rekruttering', en: 'Recruiting'),
];

List<Override> _overrides({
  BoardMembersResponse? boardMembers,
  Future<List<CampusBenefit>> Function()? benefits,
}) => [
  campusProvider(_campusId).overrideWith((ref) async => _campus),
  campusBenefitsProvider(_campusId).overrideWith(
    (ref) => benefits != null ? benefits() : Future.value(_benefits),
  ),
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
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
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

/// Scrolls [target] into the middle of the screen, clear of the translucent
/// header, so a tap lands on it.
Future<void> _centre(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
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

    final cover = tester.getTopLeft(find.byKey(const ValueKey('campus-cover')));
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

  testWidgets('the department count is never truncated at a large text scale', (
    tester,
  ) async {
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
  });

  testWidgets('the Event quick action pushes the events route', (tester) async {
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

  testWidgets('the Units quick action pushes the units route', (tester) async {
    await _pumpRouted(tester, _routerFromCampusDetail());
    await tester.tap(find.text('Units'));
    await tester.pumpAndSettle();

    expect(find.text('UNITS_ROUTE'), findsOneWidget);
    expect(find.text('EVENTS_ROUTE'), findsNothing);
    expect(find.text('PRODUCTS_ROUTE'), findsNothing);
    expect(find.text('VOLUNTEER_ROUTE'), findsNothing);
  });

  Future<void> pumpEn(
    WidgetTester tester, {
    Future<List<CampusBenefit>> Function()? benefits,
    Locale locale = const Locale('en'),
  }) async {
    await pumpBisoScreen(
      tester,
      const CampusDetailScreen(campusId: _campusId),
      overrides: _overrides(benefits: benefits),
      locale: locale,
      routed: true,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('five benefit sections show with their labels, in order', (
    tester,
  ) async {
    await pumpEn(tester);
    await tester.dragUntilVisible(
      find.text('For businesses'),
      find.byType(CustomScrollView),
      const Offset(0, -300),
    );
    final labels = [
      'Member benefits',
      'Career benefits',
      'Social network',
      'Safety and support',
      'For businesses',
    ];
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
    }
    final ys = [for (final l in labels) tester.getTopLeft(find.text(l)).dy];
    expect(ys, [...ys]..sort());
  });

  testWidgets('a section shows three titles and toggles "Show 2 more"', (
    tester,
  ) async {
    await pumpEn(tester);
    await tester.dragUntilVisible(
      find.text('Show 2 more'),
      find.byType(CustomScrollView),
      const Offset(0, -300),
    );
    expect(find.text('Free entry'), findsOneWidget);
    expect(find.text('Coffee discount'), findsOneWidget);
    expect(find.text('Mentor programme'), findsNothing);

    await _centre(tester, find.text('Show 2 more'));
    await tester.tap(find.text('Show 2 more'));
    await tester.pumpAndSettle();
    expect(find.text('Mentor programme'), findsOneWidget);
    expect(find.text('Book discount'), findsOneWidget);

    await tester.tap(find.text('Show fewer'));
    await tester.pumpAndSettle();
    expect(find.text('Mentor programme'), findsNothing);
  });

  testWidgets('titles and labels come out in Norwegian for locale no', (
    tester,
  ) async {
    await pumpEn(tester, locale: const Locale('no'));
    await tester.dragUntilVisible(
      find.text('Vis 2 til'),
      find.byType(CustomScrollView),
      const Offset(0, -300),
    );
    expect(find.text('Medlemsfordeler'), findsOneWidget);
    expect(find.text('Gratis inngang'), findsOneWidget);
    expect(find.text('Free entry'), findsNothing);
    await _centre(tester, find.text('Vis 2 til'));
    await tester.tap(find.text('Vis 2 til'));
    await tester.pumpAndSettle();
    expect(find.text('Vis færre'), findsOneWidget);
  });

  testWidgets('a section with no items is hidden', (tester) async {
    await pumpEn(
      tester,
      benefits: () async => [
        for (final b in _benefits)
          if (b.section != BenefitSection.social) b,
      ],
    );
    await tester.dragUntilVisible(
      find.text('For businesses'),
      find.byType(CustomScrollView),
      const Offset(0, -300),
    );
    expect(find.text('Social network'), findsNothing);
    expect(find.text('Career benefits'), findsOneWidget);
  });

  testWidgets('a benefits error shows BisoErrorState, not a crash', (
    tester,
  ) async {
    await pumpEn(
      tester,
      benefits: () => Future.error(
        const BenefitsApiException(BenefitsApiErrorKind.network),
      ),
    );
    await tester.dragUntilVisible(
      find.byType(BisoErrorState),
      find.byType(CustomScrollView),
      const Offset(0, -300),
    );
    expect(find.byType(BisoErrorState), findsOneWidget);
    expect(find.text('Member benefits'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an API without the route hides the sections silently', (
    tester,
  ) async {
    await pumpEn(
      tester,
      benefits: () => Future.error(
        const BenefitsApiException(BenefitsApiErrorKind.notDeployed),
      ),
    );
    expect(find.byType(BisoErrorState), findsNothing);
    expect(find.text('Member benefits'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a skeleton shows while the benefits load', (tester) async {
    final completer = Completer<List<CampusBenefit>>();
    await pumpBisoScreen(
      tester,
      const CampusDetailScreen(campusId: _campusId),
      overrides: _overrides(benefits: () => completer.future),
      locale: const Locale('en'),
      routed: true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(BisoSkeleton), findsOneWidget);
    completer.complete(const []);
    await tester.pumpAndSettle();
    expect(find.byType(BisoSkeleton), findsNothing);
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

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
    await tester.pumpAndSettle();
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
