import 'package:biso/core/theme/biso_colors.dart';
import 'package:biso/core/theme/biso_page.dart';
import 'package:biso/data/models/campus_benefit.dart';
import 'package:biso/presentation/widgets/benefits/benefit_spotlight.dart';
import 'package:biso/presentation/widgets/benefits/benefit_visuals.dart';
import 'package:biso/providers/benefits/benefit_showcase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../helpers/biso_screen_harness.dart';

const _nbsp = ' ';

CampusBenefit _deal(
  String id, {
  String title = 'GoBowl',
  String? description = '15 % på bowling hele uka.',
  DateTime? end,
}) => CampusBenefit(
  id: id,
  campusId: '3',
  section: BenefitSection.member,
  title: BenefitText(nb: title),
  description: BenefitText(nb: description),
  publishEnd: end,
  redemptionType: BenefitRedemptionType.onsite,
);

final _picks = [
  FeaturedBenefit(_deal('b1'), FeaturedReason.pickedByBiso),
  FeaturedBenefit(
    _deal('b2', title: 'Los Tacos', description: 'Gratis nachos.'),
    FeaturedReason.isNew,
  ),
  FeaturedBenefit(
    _deal(
      'b3',
      title: 'Sats',
      description: null,
      end: DateTime.utc(2026, 11, 30, 12),
    ),
    FeaturedReason.endingSoon,
  ),
];

/// Stands in for the deal page the card pushes.
final _dealStub = GoRoute(
  path: '/explore/benefits/:benefitId',
  builder: (_, state) => Scaffold(
    body: Text(
      'deal ${state.pathParameters['benefitId']} '
      '${state.uri.queryParameters['campus']} '
      '${(state.extra as CampusBenefit?)?.id}',
    ),
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  List<FeaturedBenefit>? items,
  String? campusId = '3',
  BenefitSpotlightSize size = BenefitSpotlightSize.large,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => pumpBisoScreen(
  tester,
  BisoPage(
    title: 'Fordeler',
    slivers: [
      SliverToBoxAdapter(
        child: BenefitSpotlight(
          items: items ?? _picks,
          campusId: campusId,
          size: size,
        ),
      ),
    ],
  ),
  routed: true,
  locale: const Locale('no'),
  brightness: brightness,
  textScale: textScale,
  extraRoutes: [_dealStub],
);

/// The WCAG 2 contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('white text on the scrim over a white logo reads at 4.5:1', () {
    final scrim = Color.alphaBlend(
      BisoPalette.light.deep.withValues(alpha: benefitSpotlightScrimAlpha),
      Colors.white,
    );
    expect(_contrast(Colors.white, scrim), greaterThanOrEqualTo(4.5));
    final description = Color.alphaBlend(benefitSpotlightDescription, scrim);
    expect(_contrast(description, scrim), greaterThanOrEqualTo(4.5));
  });

  testWidgets('reason chips render the right labels', (tester) async {
    for (var i = 0; i < _picks.length; i++) {
      await _pump(tester, items: [_picks[i]]);
      // Date symbols load with the app's localizations.
      final day = DateFormat('d. MMM', 'no').format(DateTime(2026, 11, 30));
      final labels = ['Valgt av BISO', 'Nytt', 'Slutter $day'];
      expect(find.text(labels[i]), findsOneWidget);
      for (final other in labels) {
        if (other != labels[i]) expect(find.text(other), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a deal without a reason has no chip', (tester) async {
    await _pump(tester, items: [FeaturedBenefit(_deal('b1'), null)]);
    expect(find.text('GoBowl'), findsOneWidget);
    expect(find.text('Valgt av BISO'), findsNothing);
    expect(find.text('Nytt'), findsNothing);
  });

  testWidgets('the value is white Museo with a sun bar under it', (
    tester,
  ) async {
    await _pump(tester);
    // A deal with no picture also shows its number, in sky, on the navy
    // fallback. The value is the one outside the picture.
    final values = find
        .text('15$_nbsp%')
        .evaluate()
        .where((e) => e.findAncestorWidgetOfExactType<BenefitImage>() == null)
        .toList();
    expect(values, hasLength(1));
    final value = values.single.widget as Text;
    expect(value.style?.color, Colors.white);
    expect(value.style?.fontWeight, FontWeight.w300);
    final bar = find.descendant(
      of: find.byType(BenefitSpotlight),
      matching: find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == BisoPalette.light.marker,
      ),
    );
    expect(bar, findsWidgets);
  });

  testWidgets('a tap pushes the deal page for the campus', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('GoBowl'));
    await tester.pumpAndSettle();
    expect(find.text('deal b1 3 b1'), findsOneWidget);
  });

  testWidgets('all of BISO keeps the national campus on the link', (
    tester,
  ) async {
    await _pump(tester, campusId: null, size: BenefitSpotlightSize.compact);
    await tester.tap(find.text('GoBowl'));
    await tester.pumpAndSettle();
    expect(find.text('deal b1 national b1'), findsOneWidget);
  });

  testWidgets('each card is one button: reason, title and value', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    const label = 'Valgt av BISO, GoBowl, 15$_nbsp%';
    expect(find.bySemanticsLabel(label), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel(label)),
      isSemantics(label: label, isButton: true, hasTapAction: true),
    );
    // The parts are not read again on their own.
    expect(find.bySemanticsLabel('GoBowl'), findsNothing);
    expect(find.bySemanticsLabel('15$_nbsp%'), findsNothing);
    semantics.dispose();
  });

  testWidgets('large: one page at a time, with page dots', (tester) async {
    await _pump(tester);
    expect(find.byType(PageView), findsOneWidget);
    expect(find.byKey(benefitSpotlightDotsKey), findsOneWidget);
    expect(tester.getSize(find.byType(PageView)).height, 236);
  });

  testWidgets('large: no auto-advance', (tester) async {
    await _pump(tester);
    final before = tester.getTopLeft(find.text('GoBowl'));
    await tester.pump(const Duration(seconds: 10));
    expect(tester.getTopLeft(find.text('GoBowl')), before);
  });

  testWidgets('compact: 300 x 176 cards and no page dots', (tester) async {
    await _pump(tester, size: BenefitSpotlightSize.compact);
    expect(find.byType(PageView), findsNothing);
    expect(find.byKey(benefitSpotlightDotsKey), findsNothing);
    final card = find.ancestor(
      of: find.text('GoBowl'),
      matching: find.byType(ClipRRect),
    );
    expect(tester.getSize(card.first), const Size(300, 176));
  });

  // 70 characters, as long as the admin's titles get.
  const longTitle =
      'Bowling, biljard og shuffleboard for BISO-medlemmer hos Lucky Bowl ASA';
  const longDescription =
      '15 % på alt hele uka, også i helgene og på helligdager, så lenge '
      'du viser medlemskortet ditt i kassen.';

  for (final size in BenefitSpotlightSize.values) {
    for (final brightness in Brightness.values) {
      testWidgets('$size, $brightness, text scale 2.0, 70-character title: '
          'no overflow', (tester) async {
        expect(longTitle.length, 70);
        await _pump(
          tester,
          size: size,
          brightness: brightness,
          textScale: 2,
          items: [
            FeaturedBenefit(
              _deal('b1', title: longTitle, description: longDescription),
              FeaturedReason.endingSoon,
            ),
            FeaturedBenefit(
              _deal('b2', title: longTitle, description: longDescription),
              null,
            ),
          ],
        );
        expect(tester.takeException(), isNull);
        expect(find.text(longTitle), findsWidgets);
      });
    }
  }
}
