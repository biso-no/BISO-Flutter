import 'package:biso/data/models/board_member_model.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/presentation/screens/explore/campus_detail_screen.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/leadership/leadership_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('quick actions navigate to the matching explore route', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const CampusDetailScreen(campusId: _campusId),
      overrides: _overrides(),
      routed: true,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();

    expect(find.byType(CampusDetailScreen), findsNothing);
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
