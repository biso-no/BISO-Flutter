import 'dart:async';
import 'dart:convert';

import 'package:biso/data/models/campus_benefit.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/models/member_pass.dart';
import 'package:biso/data/models/membership_overview.dart';
import 'package:biso/data/services/benefits_api_client.dart';
import 'package:biso/presentation/screens/benefits/benefit_detail_screen.dart';
import 'package:biso/presentation/screens/profile/member_pass_presentation.dart';
import 'package:biso/presentation/widgets/benefits/benefit_action_panel.dart';
import 'package:biso/presentation/widgets/benefits/benefit_visuals.dart';
import 'package:biso/presentation/widgets/biso/biso.dart'
    show BisoPalette, BisoSkeleton;
import 'package:biso/providers/benefits/benefits_providers.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/member_pass/member_pass_provider.dart';
import 'package:biso/providers/member_pass/member_pass_session.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/biso_screen_harness.dart';
import '../../../helpers/fake_member_pass_api.dart'
    show FakeScreenPresentation, activeView;

class _FakeApi implements BenefitsApi {
  _FakeApi({this.benefits = const [], this.listError, this.pending});

  final List<CampusBenefit> benefits;
  final BenefitsApiException? listError;

  /// When set, the list waits for it.
  final Completer<List<CampusBenefit>>? pending;
  final campuses = <String?>[];

  @override
  Future<List<CampusBenefit>> fetchBenefits({String? campusId}) async {
    campuses.add(campusId);
    final wait = pending;
    if (wait != null) return wait.future;
    if (listError != null) throw listError!;
    return benefits;
  }

  @override
  Future<String> reveal(String benefitId) async => 'CODE-1234';
}

class _FakePass extends MemberPassNotifier {
  _FakePass(this.view);
  final MemberPassView view;

  @override
  MemberPassView build() => view;
}

class _Overview extends MembershipOverviewNotifier {
  @override
  Future<MembershipOverview?> build() async => null;
}

CampusModel _campus(String id, String name) => CampusModel(
  id: id,
  name: name,
  description: '',
  location: name,
  imageUrl: '',
  heroImageUrl: '',
  stats: const CampusStats(),
);

const _title = 'Graffi Grill';

CampusBenefit _deal({
  String id = 'b1',
  String title = _title,
  String campusId = '3',
  String? category = 'food_drink',
  String? description = '25 % rabatt på hele menyen for BISO-medlemmer.',
  String? terms,
  BenefitPartner? partner,
  BenefitRedemptionType type = BenefitRedemptionType.onsite,
  bool featured = false,
  DateTime? end,
  BenefitSection section = BenefitSection.member,
  String? image,
}) => CampusBenefit(
  id: id,
  campusId: campusId,
  section: section,
  category: category,
  title: BenefitText(nb: title),
  description: BenefitText(nb: description),
  terms: BenefitText(nb: terms),
  imageUrl: image,
  redemptionType: type,
  isFeatured: featured,
  partner: partner,
  publishEnd: end,
);

/// The app's overrides for the deal page. [campus] stands in for the Home
/// campus (`filterCampusProvider` and `campusInitializedProvider`).
List<Override> _overrides(
  _FakeApi api, {
  MemberPassView? pass,
  List<Uri>? opened,
  List<Override>? campus,
}) => [
  benefitsApiProvider.overrideWithValue(api),
  memberPassProvider.overrideWith(() => _FakePass(pass ?? activeView())),
  membershipOverviewProvider.overrideWith(_Overview.new),
  screenPresentationProvider.overrideWithValue(FakeScreenPresentation()),
  benefitClockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 10, 12)),
  ...(campus ??
      [
        filterCampusProvider.overrideWithValue(_campus('3', 'Trondheim')),
        campusInitializedProvider.overrideWithValue(true),
      ]),
  switcherCampusesProvider.overrideWith(
    (_) async => [_campus('1', 'Oslo'), _campus('3', 'Trondheim')],
  ),
  if (opened != null)
    benefitLinkOpenerProvider.overrideWithValue((uri) async {
      opened.add(uri);
      return true;
    }),
];

/// Stands in for a deal the page pushes.
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

final _membershipStub = GoRoute(
  path: '/profile/membership',
  builder: (_, _) => const Scaffold(body: Text('membership page')),
);

Future<_FakeApi> _pump(
  WidgetTester tester, {
  _FakeApi? api,
  String benefitId = 'b1',
  String? campusId = '3',
  CampusBenefit? initial,
  MemberPassView? pass,
  List<Uri>? opened,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('no'),
}) async {
  final fake = api ?? _FakeApi();
  await pumpBisoScreen(
    tester,
    BenefitDetailScreen(
      benefitId: benefitId,
      campusId: campusId,
      initial: initial,
    ),
    routed: true,
    locale: locale,
    textScale: textScale,
    brightness: brightness,
    extraRoutes: [_dealStub, _membershipStub],
    overrides: _overrides(fake, pass: pass, opened: opened),
  );
  return fake;
}

/// Opens [location] through the app's own deal route, the way a link does.
Future<_FakeApi> _open(
  WidgetTester tester,
  String location, {
  required _FakeApi api,
  List<Override>? campus,
}) async {
  await pumpBisoScreen(
    tester,
    const Text('start'),
    routed: true,
    locale: const Locale('no'),
    extraRoutes: [
      GoRoute(
        path: '/explore/benefits',
        builder: (_, _) => const SizedBox.shrink(),
        routes: [benefitDetailRoute()],
      ),
    ],
    overrides: _overrides(api, campus: campus),
  );
  GoRouter.of(tester.element(find.text('start'))).go(location);
  await tester.pumpAndSettle();
  return api;
}

/// The page body, without the compact title in the header.
Finder _body(Finder matching) =>
    find.descendant(of: find.byType(CustomScrollView), matching: matching);

/// "Mer innen": the one horizontal row on the page.
Finder get _moreRow => find.byWidgetPredicate(
  (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
);

const _gone = 'Denne fordelen er ikke lenger tilgjengelig.';

/// "25 %", written with a no-break space.
const _quarterOff = '25\u00a0%';

/// The page's own scroll view, not the "Mer innen" row inside it.
Finder get _page => find
    .descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    )
    .first;

/// Scrolls [finder] to the middle of the page, clear of the tab bar.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: _page);
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
}

/// Scrolls to the end, so every sliver has been built.
Future<void> _scrollToEnd(WidgetTester tester) async {
  await tester.drag(_page, const Offset(0, -4000));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders a passed-in deal before the list arrives', (
    tester,
  ) async {
    final api = await _pump(
      tester,
      api: _FakeApi(pending: Completer()),
      initial: _deal(),
    );
    expect(_body(find.text(_title)), findsOneWidget);
    expect(_body(find.text(_quarterOff)), findsWidgets);
    expect(find.text('rabatt for medlemmer'), findsOneWidget);
    expect(find.byType(BenefitActionPanel), findsOneWidget);
    expect(find.text('Vis medlemskortet i kassen'), findsOneWidget);
    expect(find.byType(BisoSkeleton), findsNothing);
    // The list is still asked for: it fills in the reason and "Mer innen".
    expect(api.campuses, ['3']);
    await _scrollToEnd(tester);
    expect(find.textContaining('Mer innen'), findsNothing);
  });

  testWidgets('loads a deal by id when nothing is passed in', (tester) async {
    final api = await _pump(
      tester,
      api: _FakeApi(
        benefits: [
          _deal(id: 'other', title: 'Annet'),
          _deal(),
        ],
      ),
    );
    expect(api.campuses, ['3']);
    expect(_body(find.text(_title)), findsOneWidget);
    expect(find.byType(BenefitActionPanel), findsOneWidget);
  });

  testWidgets('shows a skeleton while a deal with no extra loads', (
    tester,
  ) async {
    await _pump(tester, api: _FakeApi(pending: Completer()));
    expect(find.byType(BisoSkeleton), findsOneWidget);
    expect(find.text(_gone), findsNothing);
  });

  testWidgets('a deal that is gone says so', (tester) async {
    await _pump(tester, api: _FakeApi());
    expect(find.text(_gone), findsOneWidget);
    expect(find.byType(BenefitActionPanel), findsNothing);
  });

  testWidgets('an API without the route says the deal is gone', (tester) async {
    await _pump(
      tester,
      api: _FakeApi(
        listError: const BenefitsApiException(BenefitsApiErrorKind.notDeployed),
      ),
    );
    expect(find.text(_gone), findsOneWidget);
    expect(find.text('Prøv igjen'), findsNothing);
  });

  testWidgets('a failed load offers a retry that fetches again', (
    tester,
  ) async {
    final api = await _pump(
      tester,
      api: _FakeApi(
        listError: const BenefitsApiException(BenefitsApiErrorKind.network),
      ),
    );
    expect(find.text(_gone), findsNothing);
    await tester.tap(find.text('Prøv igjen'));
    await tester.pump();
    await tester.pump();
    expect(api.campuses, ['3', '3']);
  });

  testWidgets('a failed load keeps a passed-in deal on screen', (tester) async {
    await _pump(
      tester,
      api: _FakeApi(
        listError: const BenefitsApiException(BenefitsApiErrorKind.network),
      ),
      initial: _deal(),
    );
    expect(_body(find.text(_title)), findsOneWidget);
    expect(find.text('Prøv igjen'), findsNothing);
  });

  testWidgets('no image shows the fallback number', (tester) async {
    await _pump(tester, initial: _deal());
    expect(
      find.descendant(
        of: find.byType(BenefitImage),
        matching: find.text(_quarterOff),
      ),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byType(BenefitImage)).height,
      moreOrLessEquals(300),
    );
  });

  testWidgets('"Gratis" and prices show the value without "rabatt"', (
    tester,
  ) async {
    await _pump(
      tester,
      initial: _deal(title: 'Gratis kaffe', description: null),
    );
    expect(_body(find.text('Gratis')), findsWidgets);
    expect(find.text('rabatt for medlemmer'), findsNothing);
  });

  testWidgets('no discount leaves the large row out', (tester) async {
    await _pump(
      tester,
      initial: _deal(title: 'Kaffe', description: 'Hyggelig sted.'),
    );
    expect(find.text('rabatt for medlemmer'), findsNothing);
  });

  testWidgets('chips show the category, and the reason once the list is in', (
    tester,
  ) async {
    final deal = _deal(featured: true);
    await _pump(
      tester,
      api: _FakeApi(benefits: [deal]),
      initial: deal,
    );
    expect(find.text('Mat og drikke'), findsOneWidget);
    expect(find.text('Valgt av BISO'), findsOneWidget);
  });

  testWidgets('description renders stored HTML, not its markup', (
    tester,
  ) async {
    await _pump(
      tester,
      initial: _deal(
        description: '<p>Én kaffe&nbsp;<strong>per uke</strong>.</p>',
      ),
    );
    expect(find.text('Om tilbudet'), findsOneWidget);
    expect(
      find.textContaining('Én kaffe per uke.', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('<', findRichText: true), findsNothing);
  });

  testWidgets('no description: no "Om tilbudet"', (tester) async {
    await _pump(tester, initial: _deal(description: null));
    expect(find.text('Om tilbudet'), findsNothing);
  });

  testWidgets('no terms: no "Vilkår"', (tester) async {
    await _pump(tester, initial: _deal());
    await _scrollToEnd(tester);
    expect(find.text('Vilkår'), findsNothing);
  });

  testWidgets('the terms fold open, Plate copy rendered as text', (
    tester,
  ) async {
    final terms = jsonEncode([
      {
        'type': 'p',
        'children': [
          {'text': 'Gjelder '},
          {'text': 'hverdager', 'bold': true},
          {'text': '.'},
        ],
      },
    ]);
    await _pump(tester, initial: _deal(terms: terms));
    expect(
      find.textContaining('Gjelder hverdager.', findRichText: true),
      findsNothing,
    );
    await _scrollTo(tester, find.text('Vilkår'));
    await tester.tap(find.text('Vilkår'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Gjelder hverdager.', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('"type"', findRichText: true), findsNothing);
  });

  testWidgets('"Gyldig" names the end date, else "Til videre"', (tester) async {
    await _pump(tester, initial: _deal(end: DateTime.utc(2026, 12, 31, 12)));
    expect(find.text('Gyldig'), findsOneWidget);
    expect(find.text('Til 31. desember 2026'), findsOneWidget);
  });

  testWidgets('no end date reads "Til videre"', (tester) async {
    await _pump(tester, initial: _deal());
    expect(find.text('Til videre'), findsOneWidget);
  });

  testWidgets('"Nettside" opens the partner website outside the app', (
    tester,
  ) async {
    final opened = <Uri>[];
    await _pump(
      tester,
      initial: _deal(
        partner: const BenefitPartner(
          id: 'p1',
          name: 'Graffi',
          websiteUrl: 'https://www.graffi.no/meny',
        ),
      ),
      opened: opened,
    );
    expect(find.text('graffi.no'), findsOneWidget);
    await _scrollTo(tester, find.text('Nettside'));
    await tester.tap(find.text('Nettside'));
    await tester.pump();
    expect(opened, [Uri.parse('https://www.graffi.no/meny')]);
  });

  testWidgets('a website that is not https is left out', (tester) async {
    await _pump(
      tester,
      initial: _deal(
        partner: const BenefitPartner(
          id: 'p1',
          name: 'Graffi',
          websiteUrl: 'http://graffi.no',
        ),
      ),
    );
    expect(find.text('Nettside'), findsNothing);
  });

  testWidgets('a partner shows its name', (tester) async {
    await _pump(
      tester,
      initial: _deal(
        partner: const BenefitPartner(id: 'p1', name: 'Graffi AS'),
      ),
    );
    expect(find.text('Graffi AS'), findsOneWidget);
    expect(find.text('Trondheim'), findsNothing);
  });

  testWidgets('no partner shows the campus name', (tester) async {
    await _pump(tester, initial: _deal());
    expect(find.text('Trondheim'), findsOneWidget);
  });

  testWidgets('no partner on another campus takes the switcher name', (
    tester,
  ) async {
    await _pump(
      tester,
      campusId: '1',
      initial: _deal(campusId: '1'),
    );
    await tester.pump();
    expect(find.text('Oslo'), findsOneWidget);
  });

  testWidgets('an all-of-BISO deal shows "Hele BISO"', (tester) async {
    await _pump(tester, campusId: null, initial: _deal(campusId: '5'));
    expect(find.text('Hele BISO'), findsOneWidget);
  });

  testWidgets('"Mer innen" lists other deals of the category and leaves this '
      'one out', (tester) async {
    final deal = _deal();
    final api = _FakeApi(
      benefits: [
        deal,
        _deal(id: 'b2', title: 'Egon Solsiden'),
        _deal(id: 'b3', title: 'GoBowl'),
        _deal(id: 'b4', title: 'Bertoni', category: 'shopping'),
        _deal(id: 'b5', title: 'Karrieredag', section: BenefitSection.career),
      ],
    );
    await _pump(tester, api: api, initial: deal);
    await _scrollTo(tester, find.text('Mer innen mat og drikke'));
    expect(find.text('Mer innen mat og drikke'), findsOneWidget);
    expect(
      find.descendant(of: _moreRow, matching: find.text('Egon Solsiden')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _moreRow, matching: find.text('GoBowl')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _moreRow, matching: find.text(_title)),
      findsNothing,
    );
    expect(find.text('Bertoni'), findsNothing);
    expect(find.text('Karrieredag'), findsNothing);
  });

  testWidgets('"Annet" deals get their own heading, "Flere tilbud"', (
    tester,
  ) async {
    // A missing category is "other" too.
    final deal = _deal(category: 'other');
    await _pump(
      tester,
      api: _FakeApi(
        benefits: [
          deal,
          _deal(id: 'b2', title: 'Egon Solsiden', category: null),
        ],
      ),
      initial: deal,
    );
    await _scrollTo(tester, _moreRow);
    expect(find.text('Flere tilbud'), findsOneWidget);
    expect(find.textContaining('Mer innen'), findsNothing);
  });

  for (final (category, heading) in [
    ('other', 'More deals'),
    ('food_drink', 'More in Food & drink'),
  ]) {
    testWidgets('in English, $category reads "$heading"', (tester) async {
      final deal = _deal(category: category);
      await _pump(
        tester,
        api: _FakeApi(
          benefits: [
            deal,
            _deal(id: 'b2', title: 'Egon Solsiden', category: category),
          ],
        ),
        initial: deal,
        locale: const Locale('en'),
      );
      await _scrollTo(tester, _moreRow);
      expect(find.text(heading), findsOneWidget);
      expect(find.text('More in Other'), findsNothing);
    });
  }

  testWidgets('a "Mer innen" deal with no picture shows its number once', (
    tester,
  ) async {
    final deal = _deal();
    await _pump(
      tester,
      api: _FakeApi(
        benefits: [
          deal,
          _deal(id: 'b2', title: 'Egon Solsiden'),
        ],
      ),
      initial: deal,
    );
    await _scrollTo(tester, _moreRow);
    final card = find.ancestor(
      of: find.text('Egon Solsiden'),
      matching: find.byType(InkWell),
    );
    // On the navy tile, and not again in a badge.
    expect(
      find.descendant(
        of: card,
        matching: find.descendant(
          of: find.byType(BenefitImage),
          matching: find.text(_quarterOff),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.byType(BenefitBadge)),
      findsNothing,
    );
    expect(
      find.descendant(of: _moreRow, matching: find.text('\u221225\u00a0%')),
      findsNothing,
    );
  });

  testWidgets('a "Mer innen" deal with a picture keeps its badge', (
    tester,
  ) async {
    final deal = _deal();
    await _pump(
      tester,
      api: _FakeApi(
        benefits: [
          deal,
          _deal(
            id: 'b2',
            title: 'Egon Solsiden',
            image: 'https://img.test/b2.png',
          ),
        ],
      ),
      initial: deal,
    );
    await _scrollTo(tester, _moreRow);
    expect(
      find.descendant(of: _moreRow, matching: find.byType(BenefitBadge)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _moreRow, matching: find.text('\u221225\u00a0%')),
      findsOneWidget,
    );
    final image = tester.widget<BenefitImage>(
      find.descendant(of: _moreRow, matching: find.byType(BenefitImage)),
    );
    expect(image.showHighlight, isFalse);
  });

  testWidgets('"Mer innen" shows at most eight deals', (tester) async {
    final deal = _deal();
    await _pump(
      tester,
      api: _FakeApi(
        benefits: [
          deal,
          for (var i = 0; i < 10; i++) _deal(id: 'm$i', title: 'Sted $i'),
        ],
      ),
      initial: deal,
    );
    await _scrollTo(tester, _moreRow);
    expect(
      find.descendant(of: _moreRow, matching: find.textContaining('Sted ')),
      findsNWidgets(8),
    );
  });

  testWidgets('no other deals in the category: no "Mer innen"', (tester) async {
    final deal = _deal();
    await _pump(
      tester,
      api: _FakeApi(
        benefits: [
          deal,
          _deal(id: 'b4', title: 'Bertoni', category: 'shopping'),
        ],
      ),
      initial: deal,
    );
    await _scrollToEnd(tester);
    expect(find.textContaining('Mer innen'), findsNothing);
  });

  testWidgets('a "Mer innen" card opens that deal on the same campus', (
    tester,
  ) async {
    final deal = _deal();
    await _pump(
      tester,
      api: _FakeApi(
        benefits: [
          deal,
          _deal(id: 'b2', title: 'Egon Solsiden'),
        ],
      ),
      initial: deal,
    );
    await _scrollTo(tester, find.text('Egon Solsiden'));
    await tester.tap(find.text('Egon Solsiden'));
    await tester.pumpAndSettle();
    expect(find.text('deal b2 3 b2'), findsOneWidget);
  });

  testWidgets('a non-member waits for the list before the count', (
    tester,
  ) async {
    final pending = Completer<List<CampusBenefit>>();
    final deal = _deal();
    await _pump(
      tester,
      api: _FakeApi(pending: pending),
      initial: deal,
      pass: const MemberPassView(
        status: PassStatus.noPass,
        noPassState: NoPassState.notMember,
      ),
    );
    expect(find.text('Bli medlem for å bruke dette tilbudet.'), findsOneWidget);

    pending.complete([
      deal,
      _deal(id: 'b2', title: 'Egon'),
      _deal(id: 'b3', title: 'Karriere', section: BenefitSection.career),
    ]);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Bli medlem for å bruke dette tilbudet og 2 andre fordeler i '
        'Trondheim.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the locked text names "Hele BISO" for the national list', (
    tester,
  ) async {
    final deal = _deal(campusId: '5');
    await _pump(
      tester,
      campusId: null,
      api: _FakeApi(
        benefits: [
          deal,
          _deal(id: 'b2', campusId: '5'),
        ],
      ),
      initial: deal,
      pass: const MemberPassView(
        status: PassStatus.noPass,
        noPassState: NoPassState.notMember,
      ),
    );
    expect(
      find.text(
        'Bli medlem for å bruke dette tilbudet og 1 annen fordel i Hele BISO.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the onsite pill opens the membership card', (tester) async {
    await _pump(tester, initial: _deal());
    await _scrollTo(tester, find.text('Vis medlemskortet'));
    await tester.tap(find.widgetWithText(FilledButton, 'Vis medlemskortet'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(MemberPassPresentation), findsOneWidget);
  });

  group('the deal route', () {
    testWidgets('a bare link looks the deal up on the Home campus', (
      tester,
    ) async {
      final api = await _open(
        tester,
        '/explore/benefits/b1',
        api: _FakeApi(benefits: [_deal()]),
      );
      expect(api.campuses, ['3']);
      expect(_body(find.text(_title)), findsOneWidget);
    });

    testWidgets('"national" is the all-of-BISO list', (tester) async {
      final api = await _open(
        tester,
        '/explore/benefits/b1?campus=national',
        api: _FakeApi(benefits: [_deal(campusId: '5')]),
      );
      expect(api.campuses, [null]);
      expect(_body(find.text(_title)), findsOneWidget);
    });

    testWidgets('a named campus is that campus', (tester) async {
      final api = await _open(
        tester,
        '/explore/benefits/b1?campus=1',
        api: _FakeApi(benefits: [_deal(campusId: '1')]),
      );
      expect(api.campuses, ['1']);
    });

    testWidgets('a bare link waits for the Home campus to load', (
      tester,
    ) async {
      final ready = StateProvider<bool>((_) => false);
      final api = await _open(
        tester,
        '/explore/benefits/b1',
        api: _FakeApi(benefits: [_deal()]),
        campus: [
          campusInitializedProvider.overrideWith((ref) => ref.watch(ready)),
          filterCampusProvider.overrideWith(
            (ref) =>
                ref.watch(ready) ? _campus('3', 'Trondheim') : _campus('', ''),
          ),
        ],
      );
      expect(find.byType(BisoSkeleton), findsOneWidget);
      expect(find.text(_gone), findsNothing);
      expect(api.campuses, isEmpty);

      ProviderScope.containerOf(
        tester.element(find.byType(BisoSkeleton)),
      ).read(ready.notifier).state = true;
      await tester.pumpAndSettle();
      expect(api.campuses, ['3']);
      expect(_body(find.text(_title)), findsOneWidget);
    });

    testWidgets('a bare link with no Home campus uses all of BISO', (
      tester,
    ) async {
      final api = await _open(
        tester,
        '/explore/benefits/b1',
        api: _FakeApi(benefits: [_deal(campusId: '5')]),
        campus: [
          filterCampusProvider.overrideWithValue(_campus('', '')),
          campusInitializedProvider.overrideWithValue(true),
        ],
      );
      expect(api.campuses, [null]);
      expect(_body(find.text(_title)), findsOneWidget);
    });
  });

  testWidgets('the website is written in BISO blue', (tester) async {
    await _pump(
      tester,
      initial: _deal(
        partner: const BenefitPartner(
          id: 'p1',
          name: 'Graffi',
          websiteUrl: 'https://graffi.no',
        ),
      ),
    );
    final value = tester.widget<Text>(find.text('graffi.no'));
    expect(value.style?.color, BisoPalette.light.link);
    final valid = tester.widget<Text>(find.text('Til videre'));
    expect(valid.style?.color, BisoPalette.light.muted);
  });

  testWidgets('a "Mer innen" card is one button: title and deal', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final deal = _deal();
    await _pump(
      tester,
      api: _FakeApi(
        benefits: [
          deal,
          _deal(id: 'b2', title: 'Egon Solsiden'),
          _deal(id: 'b3', title: 'Bowl', description: null),
        ],
      ),
      initial: deal,
    );
    await _scrollTo(tester, _moreRow);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Egon Solsiden, $_quarterOff')),
      isSemantics(
        label: 'Egon Solsiden, $_quarterOff',
        isButton: true,
        hasTapAction: true,
      ),
    );
    // No discount: the title alone.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Bowl')),
      isSemantics(isButton: true, hasTapAction: true),
    );
    // The badge and the lines are not read again on their own.
    expect(find.bySemanticsLabel('Egon Solsiden'), findsNothing);
    expect(find.bySemanticsLabel('−25\u00a0%'), findsNothing);
    semantics.dispose();
  });

  for (final brightness in Brightness.values) {
    testWidgets('text scale 2.0 with a 70-char title: no overflow '
        '($brightness)', (tester) async {
      final title = 'Graffi Grill ' * 5 + 'Solsiden'; // 73 characters
      expect(title.length, greaterThanOrEqualTo(70));
      final deal = _deal(
        title: '25 % $title',
        terms: 'Gjelder hverdager.',
        end: DateTime.utc(2026, 12, 31, 12),
        featured: true,
        partner: const BenefitPartner(
          id: 'p1',
          name: 'Graffi Grill Solsiden Trondheim Sentrum AS',
          websiteUrl: 'https://www.graffi-grill-solsiden-trondheim.no',
        ),
      );
      await _pump(
        tester,
        api: _FakeApi(
          benefits: [
            deal,
            _deal(id: 'b2', title: '1500 kr $title'),
            _deal(id: 'b3', title: 'Gratis $title'),
          ],
        ),
        initial: deal,
        textScale: 2,
        brightness: brightness,
      );
      expect(tester.takeException(), isNull);
      await _scrollTo(tester, find.text('Vilkår'));
      await tester.tap(find.text('Vilkår'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
