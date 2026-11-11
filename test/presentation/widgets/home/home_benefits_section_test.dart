import 'package:biso/core/theme/biso_page.dart';
import 'package:biso/data/models/campus_benefit.dart';
import 'package:biso/data/services/benefits_api_client.dart';
import 'package:biso/presentation/widgets/home/home_benefits_section.dart';
import 'package:biso/providers/benefits/benefits_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/biso_screen_harness.dart';

CampusBenefit _deal(
  String id, {
  String title = 'GoBowl',
  bool featured = false,
  DateTime? created,
}) => CampusBenefit(
  id: id,
  campusId: '3',
  section: BenefitSection.member,
  title: BenefitText(nb: title),
  description: const BenefitText(nb: '15 % på bowling.'),
  isFeatured: featured,
  createdAt: created,
  redemptionType: BenefitRedemptionType.onsite,
);

final _benefitsStub = GoRoute(
  path: '/explore/benefits',
  builder: (_, _) => const Scaffold(body: Text('benefits screen')),
);

Future<void> _pump(
  WidgetTester tester,
  Future<List<CampusBenefit>> Function() load,
) => pumpBisoScreen(
  tester,
  const BisoPage(
    title: 'Hjem',
    slivers: [HomeBenefitsSection(campusId: '3')],
  ),
  routed: true,
  locale: const Locale('no'),
  extraRoutes: [_benefitsStub],
  overrides: [campusBenefitsProvider('3').overrideWith((_) => load())],
);

void main() {
  testWidgets('shows Utvalgt items with reasons', (tester) async {
    await _pump(
      tester,
      () async => [_deal('a', featured: true), _deal('b', title: 'Sats')],
    );
    await tester.pump();
    expect(find.text('Fordeler for deg'), findsOneWidget);
    expect(find.text('Vis alle'), findsOneWidget);
    expect(find.text('GoBowl'), findsOneWidget);
    expect(find.text('Valgt av BISO'), findsOneWidget);
    expect(find.text('Sats'), findsNothing);
  });

  testWidgets('falls back to the first deals without reason chips', (
    tester,
  ) async {
    await _pump(tester, () async => [_deal('a'), _deal('b', title: 'Sats')]);
    await tester.pump();
    expect(find.text('GoBowl'), findsOneWidget);
    expect(find.text('Sats'), findsOneWidget);
    expect(find.text('Valgt av BISO'), findsNothing);
    expect(find.text('Nytt'), findsNothing);
  });

  testWidgets('hidden with no deals', (tester) async {
    await _pump(tester, () async => []);
    await tester.pump();
    expect(find.text('Fordeler for deg'), findsNothing);
    expect(find.text('Vis alle'), findsNothing);
  });

  testWidgets('hidden on error', (tester) async {
    await _pump(tester, () async => throw Exception('boom'));
    await tester.pump();
    expect(find.text('Fordeler for deg'), findsNothing);
  });

  testWidgets('hidden on notDeployed', (tester) async {
    await _pump(
      tester,
      () async => throw const BenefitsApiException(
        BenefitsApiErrorKind.notDeployed,
        statusCode: 404,
      ),
    );
    await tester.pump();
    expect(find.text('Fordeler for deg'), findsNothing);
    expect(find.text('Vis alle'), findsNothing);
  });

  testWidgets('"Vis alle" goes to /explore/benefits', (tester) async {
    await _pump(tester, () async => [_deal('a')]);
    await tester.pump();
    await tester.tap(find.text('Vis alle'));
    await tester.pumpAndSettle();
    expect(find.text('benefits screen'), findsOneWidget);
  });
}
