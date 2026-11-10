import 'package:biso/core/theme/biso_colors.dart';
import 'package:biso/core/theme/biso_page.dart';
import 'package:biso/data/models/campus_benefit.dart';
import 'package:biso/presentation/widgets/benefits/benefit_grid.dart';
import 'package:biso/presentation/widgets/benefits/benefit_visuals.dart';
import 'package:biso/providers/benefits/benefit_standing.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/biso_screen_harness.dart';

const _nbsp = '\u00A0';
const _minus = '\u2212';

CampusBenefit _deal(
  String id, {
  String title = 'GoBowl',
  String? description = '15 % på bowling hele uka.',
  BenefitRedemptionType type = BenefitRedemptionType.onsite,
  String? image,
  String? category,
}) => CampusBenefit(
  id: id,
  campusId: '3',
  section: BenefitSection.member,
  category: category,
  title: BenefitText(nb: title),
  description: BenefitText(nb: description),
  imageUrl: image,
  redemptionType: type,
);

/// One deal per way of claiming it, none with a discount in its text.
final _byType = [
  _deal('onsite', title: 'Sats', description: 'Trening hele året.'),
  _deal(
    'code',
    title: 'Adobe',
    description: 'Programvare for studiet.',
    type: BenefitRedemptionType.code,
  ),
  _deal(
    'link',
    title: 'Ticketmaster',
    description: 'Billetter til konserter.',
    type: BenefitRedemptionType.link,
  ),
  _deal(
    'none',
    title: 'Bokhandel',
    description: 'Fordeler i butikken.',
    type: BenefitRedemptionType.none,
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

Future<void> _pumpGrid(
  WidgetTester tester, {
  required List<CampusBenefit> deals,
  BenefitStanding standing = BenefitStanding.member,
  String? campusId = '3',
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => pumpBisoScreen(
  tester,
  BisoPage(
    title: 'Fordeler',
    slivers: [
      benefitGridSliver(deals: deals, standing: standing, campusId: campusId),
    ],
  ),
  routed: true,
  locale: const Locale('no'),
  brightness: brightness,
  textScale: textScale,
  extraRoutes: [_dealStub],
);

Future<void> _pumpChips(
  WidgetTester tester, {
  required List<String> categories,
  String? selected,
  ValueChanged<String?>? onSelected,
}) => pumpBisoScreen(
  tester,
  BisoPage(
    title: 'Fordeler',
    slivers: [
      SliverToBoxAdapter(
        child: BenefitCategoryChips(
          categories: categories,
          selected: selected,
          onSelected: onSelected ?? (_) {},
        ),
      ),
    ],
  ),
  locale: const Locale('no'),
);

void main() {
  group('grid card', () {
    testWidgets('the claim line follows the redemption type for a member', (
      tester,
    ) async {
      await _pumpGrid(tester, deals: _byType);
      expect(find.text('Vis kortet i kassen'), findsOneWidget);
      expect(find.text('Rabattkode'), findsOneWidget);
      expect(find.text('Lenke'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.creditcard), findsOneWidget);
      expect(find.text('Bare for medlemmer'), findsNothing);
      expect(find.byIcon(CupertinoIcons.lock), findsNothing);

      // A deal claimed no particular way has no claim line at all.
      final none = find.ancestor(
        of: find.text('Bokhandel'),
        matching: find.byType(BenefitGridCard),
      );
      for (final claim in ['Vis kortet i kassen', 'Rabattkode', 'Lenke']) {
        expect(
          find.descendant(of: none, matching: find.text(claim)),
          findsNothing,
        );
      }
      expect(
        find.descendant(of: none, matching: find.byType(Icon)),
        findsOneWidget, // The category icon on the navy fallback only.
      );
    });

    for (final standing in [
      BenefitStanding.notMember,
      BenefitStanding.signedOut,
    ]) {
      testWidgets('non-members and signed-out see "Bare for medlemmer" on '
          'every card ($standing)', (tester) async {
        await _pumpGrid(tester, deals: _byType, standing: standing);
        expect(find.text('Bare for medlemmer'), findsNWidgets(4));
        expect(find.byIcon(CupertinoIcons.lock), findsNWidgets(4));
        expect(find.text('Vis kortet i kassen'), findsNothing);
        expect(find.text('Rabattkode'), findsNothing);
        expect(find.text('Lenke'), findsNothing);
        expect(find.byIcon(CupertinoIcons.creditcard), findsNothing);
      });
    }

    for (final standing in [
      BenefitStanding.checking,
      BenefitStanding.unavailable,
      BenefitStanding.upcoming,
      BenefitStanding.needsBi,
    ]) {
      testWidgets('checking keeps the normal claim line ($standing)', (
        tester,
      ) async {
        await _pumpGrid(tester, deals: _byType, standing: standing);
        expect(find.text('Vis kortet i kassen'), findsOneWidget);
        expect(find.text('Rabattkode'), findsOneWidget);
        expect(find.text('Lenke'), findsOneWidget);
        expect(find.text('Bare for medlemmer'), findsNothing);
        expect(find.byIcon(CupertinoIcons.lock), findsNothing);
      });
    }

    testWidgets('a deal with a picture carries its discount in a badge', (
      tester,
    ) async {
      await _pumpGrid(
        tester,
        deals: [_deal('b1', image: 'https://img.test/b1.png')],
      );
      expect(find.byType(BenefitBadge), findsOneWidget);
      expect(find.text('${_minus}15$_nbsp%'), findsOneWidget);
      expect(find.text('15$_nbsp%'), findsNothing);
      final image = tester.widget<BenefitImage>(find.byType(BenefitImage));
      expect(image.memCacheWidth, 600);
    });

    testWidgets('a deal with no picture shows its number once, on the navy '
        'tile', (tester) async {
      await _pumpGrid(tester, deals: [_deal('b1')]);
      expect(find.byType(BenefitBadge), findsNothing);
      expect(
        find.descendant(
          of: find.byType(BenefitImage),
          matching: find.text('15$_nbsp%'),
        ),
        findsOneWidget,
      );
      expect(find.text('${_minus}15$_nbsp%'), findsNothing);
    });

    testWidgets('a card is the surface colour with an 18 pt radius', (
      tester,
    ) async {
      await _pumpGrid(tester, deals: [_deal('b1')]);
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(BenefitGridCard),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, BisoPalette.light.surface);
      expect(material.borderRadius, BorderRadius.circular(18));
      final title = tester.widget<Text>(find.text('GoBowl'));
      expect(title.style?.fontSize, 15);
      expect(title.style?.fontWeight, FontWeight.w600);
      final description = tester.widget<Text>(
        find.text('15 % på bowling hele uka.'),
      );
      expect(description.maxLines, 2);
      expect(description.style?.color, BisoPalette.light.muted);
    });

    testWidgets('a tap pushes the deal page for the campus', (tester) async {
      await _pumpGrid(tester, deals: [_deal('b1'), _deal('b2')]);
      await tester.tap(find.text('GoBowl').last);
      await tester.pumpAndSettle();
      expect(find.text('deal b2 3 b2'), findsOneWidget);
    });

    testWidgets('all of BISO keeps the national campus on the link', (
      tester,
    ) async {
      await _pumpGrid(tester, deals: [_deal('b1')], campusId: null);
      await tester.tap(find.text('GoBowl'));
      await tester.pumpAndSettle();
      expect(find.text('deal b1 national b1'), findsOneWidget);
    });

    testWidgets('each card is one button: title, badge and claim line', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpGrid(tester, deals: [_deal('b1'), _byType[1], _byType[3]]);
      const label = 'GoBowl, ${_minus}15$_nbsp%, Vis kortet i kassen';
      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        isSemantics(label: label, isButton: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Adobe, Rabattkode')),
        isSemantics(
          label: 'Adobe, Rabattkode',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Bokhandel')),
        isSemantics(label: 'Bokhandel', isButton: true, hasTapAction: true),
      );
      // The parts are not read again on their own.
      expect(find.bySemanticsLabel('GoBowl'), findsNothing);
      expect(find.bySemanticsLabel('Vis kortet i kassen'), findsNothing);
      expect(find.bySemanticsLabel('15 % på bowling hele uka.'), findsNothing);
      semantics.dispose();
    });

    testWidgets('a non-member hears "Bare for medlemmer" on the card', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpGrid(
        tester,
        deals: [_deal('b1')],
        standing: BenefitStanding.notMember,
      );
      expect(
        find.bySemanticsLabel('GoBowl, ${_minus}15$_nbsp%, Bare for medlemmer'),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('grid', () {
    testWidgets('two cards to a row, in API order; an odd one out sits '
        'left', (tester) async {
      await _pumpGrid(tester, deals: _byType.sublist(0, 3));
      expect(find.byType(IntrinsicHeight), findsNWidgets(2));
      final sats = tester.getTopLeft(find.text('Sats'));
      final adobe = tester.getTopLeft(find.text('Adobe'));
      final ticket = tester.getTopLeft(find.text('Ticketmaster'));
      expect(adobe.dy, sats.dy);
      expect(adobe.dx, greaterThan(sats.dx));
      expect(ticket.dy, greaterThan(sats.dy));
      expect(ticket.dx, sats.dx);
      // The odd card is as wide as the others.
      final cards = find.byType(BenefitGridCard);
      expect(
        tester.getSize(cards.at(2)).width,
        tester.getSize(cards.at(0)).width,
      );
    });

    testWidgets('cards in a row match heights', (tester) async {
      await _pumpGrid(
        tester,
        deals: [
          _deal('b1', title: 'GoBowl', description: null),
          _deal(
            'b2',
            title: 'Bowling, biljard og shuffleboard hos Lucky Bowl',
            description: 'Rabatt på alt hele uka, også i helgene.',
          ),
        ],
      );
      final cards = find.byType(BenefitGridCard);
      expect(
        tester.getSize(cards.at(0)).height,
        tester.getSize(cards.at(1)).height,
      );
    });

    // 70 characters, as long as the admin's titles get.
    const longTitle =
        'Bowling, biljard og shuffleboard for BISO-medlemmer hos Lucky Bowl ASA';
    const longDescription =
        '15 % på alt hele uka, også i helgene og på helligdager, så lenge '
        'du viser medlemskortet ditt i kassen.';

    for (final brightness in Brightness.values) {
      testWidgets('text scale 2.0 with a 70-char title: grid rows grow, no '
          'overflow ($brightness)', (tester) async {
        expect(longTitle.length, 70);
        final deals = [
          _deal('b1', title: longTitle, description: longDescription),
          _deal('b2', type: BenefitRedemptionType.code),
          _deal(
            'b3',
            title: longTitle,
            description: longDescription,
            image: 'https://img.test/b3.png',
          ),
        ];
        await _pumpGrid(tester, deals: deals, brightness: brightness);
        final row = find.byType(IntrinsicHeight).first;
        final normal = tester.getSize(row).height;

        await _pumpGrid(
          tester,
          deals: deals,
          brightness: brightness,
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        expect(tester.getSize(row).height, greaterThan(normal));
        final cards = find.byType(BenefitGridCard);
        expect(
          tester.getSize(cards.at(0)).height,
          tester.getSize(cards.at(1)).height,
        );
        expect(find.text(longTitle), findsWidgets);
        expect(find.text('Vis kortet i kassen'), findsWidgets);

        // The second row, further down, lays out cleanly too.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('category chips', () {
    testWidgets('chips hide below two categories', (tester) async {
      await _pumpChips(tester, categories: const ['other']);
      expect(find.text('Alle'), findsNothing);
      expect(find.text('Annet'), findsNothing);

      await _pumpChips(tester, categories: const []);
      expect(find.text('Alle'), findsNothing);

      await _pumpChips(tester, categories: const ['food_drink', 'other']);
      expect(find.text('Alle'), findsOneWidget);
      expect(find.text('Mat og drikke'), findsOneWidget);
      expect(find.text('Annet'), findsOneWidget);
    });

    testWidgets('tapping a chip calls onSelected with its key, "Alle" with '
        'null', (tester) async {
      final picks = <String?>[];
      await _pumpChips(
        tester,
        categories: const ['food_drink', 'events'],
        selected: 'events',
        onSelected: picks.add,
      );
      await tester.tap(find.text('Mat og drikke'));
      await tester.tap(find.text('Alle'));
      expect(picks, ['food_drink', null]);
    });

    testWidgets('"Alle" comes first, then each category with its icon', (
      tester,
    ) async {
      await _pumpChips(tester, categories: const ['food_drink', 'events']);
      final all = tester.getTopLeft(find.text('Alle')).dx;
      final food = tester.getTopLeft(find.text('Mat og drikke')).dx;
      final events = tester.getTopLeft(find.text('Arrangementer')).dx;
      expect(all, lessThan(food));
      expect(food, lessThan(events));
      expect(find.byIcon(benefitCategoryIcon('food_drink')), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.calendar), findsOneWidget);
    });

    testWidgets('the selected chip is navy with white text; the rest are '
        'surface with a hairline', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpChips(
        tester,
        categories: const ['food_drink', 'events'],
        selected: 'events',
      );
      final palette = BisoPalette.light;

      BoxDecoration chipOf(String label) =>
          tester
                  .widget<DecoratedBox>(
                    find
                        .ancestor(
                          of: find.text(label),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;

      final on = chipOf('Arrangementer');
      expect(on.color, palette.deep);
      // An edge keeps the navy off the dark paper.
      expect(on.border, Border.all(color: palette.deepEdge));
      expect(
        tester.widget<Text>(find.text('Arrangementer')).style?.color,
        Colors.white,
      );
      for (final label in ['Alle', 'Mat og drikke']) {
        final off = chipOf(label);
        expect(off.color, palette.surface);
        expect(off.border, Border.all(color: palette.hairline));
        expect(tester.widget<Text>(find.text(label)).style?.color, palette.ink);
      }

      expect(
        tester.getSemantics(find.bySemanticsLabel('Arrangementer')),
        isSemantics(
          label: 'Arrangementer',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Alle')),
        isSemantics(
          label: 'Alle',
          isButton: true,
          isSelected: false,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('a chip is at least 44 pt tall to tap', (tester) async {
      await _pumpChips(tester, categories: const ['food_drink', 'events']);
      final target = find.ancestor(
        of: find.text('Alle'),
        matching: find.byType(GestureDetector),
      );
      expect(tester.getSize(target.first).height, greaterThanOrEqualTo(44));
    });

    testWidgets('text scale 2.0 in dark: chips grow, no overflow', (
      tester,
    ) async {
      await pumpBisoScreen(
        tester,
        BisoPage(
          title: 'Fordeler',
          slivers: [
            SliverToBoxAdapter(
              child: BenefitCategoryChips(
                categories: const [
                  'food_drink',
                  'health_fitness',
                  'nightlife',
                  'shopping',
                  'travel',
                  'software',
                  'events',
                  'other',
                ],
                selected: null,
                onSelected: (_) {},
              ),
            ),
          ],
        ),
        locale: const Locale('no'),
        brightness: Brightness.dark,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Alle'), findsOneWidget);
    });
  });
}
