import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/models/board_member_model.dart';
import 'package:biso/data/models/department_model.dart';
import 'package:biso/data/services/department_service.dart';
import 'package:biso/data/services/leadership_service.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:biso/presentation/screens/explore/unit_detail_screen.dart';
import 'package:biso/presentation/screens/explore/units_overview_screen.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/leadership/leadership_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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

final _departments = [
  DepartmentModel(
    id: 'd1',
    name: 'Marketing Society',
    campusId: _campus.id,
    active: true,
    description: '<p>We do marketing things.</p>',
  ),
  DepartmentModel(
    id: 'd2',
    name: 'Finance Club',
    campusId: _campus.id,
    active: true,
    logo: 'https://example.com/logo.png',
    type: 'Academic',
    description: '<p>Finance club description.</p>',
  ),
];

/// Replaces the real Appwrite-backed service. Deterministic and offline.
class _FakeDepartmentService extends DepartmentService {
  _FakeDepartmentService([List<DepartmentModel>? departments])
    : _list = departments ?? _departments;

  final List<DepartmentModel> _list;

  @override
  Future<List<DepartmentModel>> getActiveDepartmentsForCampus(
    String campusId, {
    String locale = 'en',
  }) async => _list;

  @override
  Future<DepartmentModel?> getDepartmentById(
    String id, {
    String locale = 'en',
  }) async {
    for (final dept in _list) {
      if (dept.id == id) return dept;
    }
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> getDepartmentSocials(
    String departmentId,
  ) async => const [
    {'platform': 'website', 'url': 'https://biso.no'},
    {'platform': 'instagram', 'url': 'https://instagram.com/biso'},
  ];
}

/// Replaces the BISO API board route. Records what it was asked for.
class _FakeLeadershipService extends LeadershipService {
  _FakeLeadershipService([this.members = const []]);

  final List<BoardMemberModel> members;
  final requests = <(String, String?)>[];

  @override
  Future<BoardMembersResponse> getBoardMembers({
    required String campusId,
    String? departmentId,
  }) async {
    requests.add((campusId, departmentId));
    return BoardMembersResponse(
      success: true,
      members: members,
      count: members.length,
    );
  }
}

List<Override> _overrides([
  List<DepartmentModel>? departments,
  LeadershipService? leadership,
]) => [
  filterCampusProvider.overrideWithValue(_campus),
  departmentServiceProvider.overrideWithValue(
    _FakeDepartmentService(departments),
  ),
  leadershipServiceProvider.overrideWithValue(
    leadership ?? _FakeLeadershipService(),
  ),
];

/// The real department whose card title was cut to "Campus Manage…".
const _longName = 'Campus Management Oslo';

final _longNamed = [
  DepartmentModel(
    id: 'd3',
    name: _longName,
    campusId: _campus.id,
    active: true,
    description: "<p>BISO Oslo's Campus Management team.</p>",
  ),
];

RenderParagraph _paragraphFor(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text));

void main() {
  testWidgets('overview card shows a long department name in full', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const UnitsOverviewScreen(),
      overrides: _overrides(_longNamed),
      routed: true,
    );

    expect(find.text(_longName), findsOneWidget);
    expect(
      _paragraphFor(tester, _longName).didExceedMaxLines,
      isFalse,
      reason: 'the title must wrap, not be cut with an ellipsis',
    );
  });

  testWidgets('overview card with a long name lays out at enlarged text', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const UnitsOverviewScreen(),
      overrides: _overrides(_longNamed),
      routed: true,
    );
  });

  testWidgets('Units overview builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const UnitsOverviewScreen(),
      overrides: _overrides(),
      routed: true,
    );
  });

  testWidgets('Unit detail builds on BisoPage in every appearance', (
    tester,
  ) async {
    await expectBuildsCleanly(
      tester,
      () => const UnitDetailScreen(
        departmentId: 'd1',
        departmentName: 'Marketing Society',
      ),
      overrides: _overrides(),
      routed: true,
    );
  });

  testWidgets("detail page's compact title equals the department name", (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const UnitDetailScreen(
        departmentId: 'd1',
        departmentName: 'Marketing Society',
      ),
      overrides: _overrides(),
      routed: true,
    );

    final compactTitle = tester.widget<Text>(
      find.byKey(const ValueKey('biso-compact-title')),
    );
    expect(compactTitle.data, 'Marketing Society');
  });

  testWidgets("detail page shows the department's board for its campus", (
    tester,
  ) async {
    final leadership = _FakeLeadershipService(const [
      BoardMemberModel(
        name: 'Kari Nordmann',
        email: 'kari@biso.no',
        phone: '',
        role: 'Head of Marketing',
        officeLocation: '',
      ),
      BoardMemberModel(
        name: 'Ola Hansen',
        email: 'ola@biso.no',
        phone: '',
        role: '',
        officeLocation: 'Oslo',
      ),
    ]);
    await pumpBisoScreen(
      tester,
      const UnitDetailScreen(
        departmentId: 'd1',
        departmentName: 'Marketing Society',
      ),
      overrides: _overrides(null, leadership),
      routed: true,
    );
    await tester.pumpAndSettle();

    expect(leadership.requests, [(_campus.id, 'd1')]);
    await tester.dragUntilVisible(
      find.text('Kari Nordmann'),
      find.byType(CustomScrollView),
      const Offset(0, -300),
    );
    expect(find.text('Board'), findsOneWidget);
    expect(find.text('Head of Marketing'), findsOneWidget);
    // Azure users without a job title keep just their office.
    expect(find.text('Oslo'), findsOneWidget);
  });

  testWidgets('detail page leaves the board out when it has no members', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const UnitDetailScreen(
        departmentId: 'd1',
        departmentName: 'Marketing Society',
      ),
      overrides: _overrides(),
      routed: true,
    );
    await tester.pumpAndSettle();

    expect(find.text('Board'), findsNothing);
    expect(find.textContaining('No members found'), findsNothing);
    expect(find.text('Website'), findsOneWidget);
  });

  testWidgets(
    'overview shows one card per department and tapping a card pushes the '
    'detail route',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/explore/units',
        routes: [
          GoRoute(
            path: '/explore/units',
            builder: (context, state) => const UnitsOverviewScreen(),
          ),
          GoRoute(
            path: '/explore/units/:id',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              final id = state.pathParameters['id']!;
              final name = extra?['name'] as String? ?? 'Organization';
              return UnitDetailScreen(departmentId: id, departmentName: name);
            },
          ),
        ],
      );

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

      expect(find.text('Marketing Society'), findsOneWidget);
      expect(find.text('Finance Club'), findsOneWidget);

      await tester.tap(find.text('Finance Club'));
      await tester.pumpAndSettle();

      expect(find.text('Finance Club'), findsWidgets);
      expect(find.text('Website'), findsOneWidget);
      expect(find.text('Instagram'), findsOneWidget);
    },
  );
}
