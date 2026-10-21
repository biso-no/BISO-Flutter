import 'package:biso/data/models/app_config.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/presentation/screens/explore/explore_screen.dart';
import 'package:biso/presentation/screens/news/news_detail_screen.dart';
import 'package:biso/presentation/screens/news/news_list_screen.dart';
import 'package:biso/data/models/news_model.dart';
import 'package:biso/data/services/news_service.dart';
import 'package:biso/presentation/widgets/biso/biso.dart';
import 'package:biso/providers/campus/campus_data_provider.dart';
import 'package:biso/providers/campus/campus_provider.dart';
import 'package:biso/providers/config/app_config_provider.dart';
import 'package:biso/providers/large_event/large_event_provider.dart';
import 'package:biso/providers/member_pass/scanner_access_provider.dart';
import 'package:biso/providers/membership/membership_overview_provider.dart';
import 'package:biso/providers/news/news_provider.dart';
import 'package:biso/providers/ui/locale_provider.dart';
import 'package:biso/core/theme/premium_theme.dart';
import 'package:biso/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/biso_screen_harness.dart';
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

NewsModel _news({
  String id = 'n1',
  String title = 'Autumn news',
  String body = '<p>All the autumn plans.</p>',
  String? slug = 'autumn-news',
}) => NewsModel(
  id: id,
  slug: slug,
  title: title,
  body: body,
  shortDescription: 'Short intro',
  campusId: 'oslo',
  author: 'Kari',
  publishedAt: DateTime.utc(2030, 9, 3, 17),
);

class _FakeNewsService extends NewsService {
  _FakeNewsService(this.items);
  final List<NewsModel> items;
  final campusIds = <String?>[];
  final offsets = <int>[];

  @override
  Future<List<NewsModel>> listNews({
    String? campusId,
    String locale = 'no',
    int limit = 20,
    int offset = 0,
  }) async {
    campusIds.add(campusId);
    offsets.add(offset);
    return items.skip(offset).take(limit).toList();
  }
}

List<Override> _listOverrides(
  List<NewsModel> items, {
  _FakeNewsService? service,
}) => [
  filterCampusProvider.overrideWithValue(_campus),
  newsServiceProvider.overrideWithValue(service ?? _FakeNewsService(items)),
  allCampusesProvider.overrideWith((ref) async => const [_campus]),
];

List<Override> _detailOverrides(NewsModel? news, {bool member = false}) => [
  newsDetailProvider.overrideWith((ref, idOrSlug) async => news),
  hasValidMembershipProvider.overrideWithValue(member),
];

class _Locale extends LocaleNotifier {}

void main() {
  testWidgets('the list shows the article titles', (tester) async {
    await pumpBisoScreen(
      tester,
      const NewsListScreen(),
      overrides: _listOverrides([
        _news(),
        _news(id: 'n2', title: 'Winter news'),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Autumn news'), findsOneWidget);
    expect(find.text('Winter news'), findsOneWidget);
  });

  List<NewsModel> many(int count) => [
    for (var i = 0; i < count; i++) _news(id: 'n$i', title: 'Story $i'),
  ];

  testWidgets('a full first page shows more than 6 rows', (tester) async {
    final service = _FakeNewsService(many(20));
    await pumpBisoScreen(
      tester,
      const NewsListScreen(),
      overrides: _listOverrides(const [], service: service),
    );
    await tester.pumpAndSettle();

    expect(
      find.byType(BisoListRow, skipOffstage: false).evaluate().length,
      greaterThan(6),
    );
  });

  testWidgets('scrolling to the end requests page two at offset 20', (
    tester,
  ) async {
    final service = _FakeNewsService(many(25));
    await pumpBisoScreen(
      tester,
      const NewsListScreen(),
      overrides: _listOverrides(const [], service: service),
    );
    await tester.pumpAndSettle();
    expect(service.offsets, [0]);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -20000));
    await tester.pumpAndSettle();

    expect(service.offsets, [0, 20]);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(find.text('Story 24'), findsOneWidget);
    // A short second page ends paging.
    expect(service.offsets, [0, 20]);
  });

  testWidgets('the list reads the selected campus', (tester) async {
    final service = _FakeNewsService(many(3));
    await pumpBisoScreen(
      tester,
      const NewsListScreen(),
      overrides: _listOverrides(const [], service: service),
    );
    await tester.pumpAndSettle();

    expect(service.campusIds, [_campus.id]);
  });

  testWidgets('the detail renders an HTML body', (tester) async {
    await pumpBisoScreen(
      tester,
      const NewsDetailScreen(idOrSlug: 'autumn-news'),
      overrides: _detailOverrides(_news()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Autumn news'), findsWidgets);
    expect(find.textContaining('All the autumn plans.'), findsOneWidget);
    expect(find.text('Read on biso.no'), findsNothing);
  });

  testWidgets('a Plate JSON body shows Read on biso.no, not the JSON', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const NewsDetailScreen(idOrSlug: 'autumn-news'),
      overrides: _detailOverrides(
        _news(body: '[{"type":"p","children":[{"text":"plate-secret"}]}]'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Read on biso.no'), findsOneWidget);
    expect(find.text('Short intro'), findsOneWidget);
    expect(find.textContaining('plate-secret'), findsNothing);
  });

  // News is readable by everyone, members-only articles included, so a
  // missing article is unpublished, deleted or a bad link - for a non-member
  // too.
  for (final member in [false, true]) {
    testWidgets(
      'a missing article says it is not available, '
      '${member ? 'for a member' : 'and offers no membership to a non-member'}',
      (tester) async {
        await pumpBisoScreen(
          tester,
          const NewsDetailScreen(idOrSlug: 'gone'),
          overrides: _detailOverrides(null, member: member),
        );
        await tester.pumpAndSettle();

        expect(find.text("This article isn't available"), findsOneWidget);
        expect(find.text('Members only'), findsNothing);
        expect(find.text('Become a member'), findsNothing);
      },
    );
  }

  testWidgets('both screens build on BisoPage', (tester) async {
    await pumpBisoScreen(
      tester,
      const NewsListScreen(),
      overrides: _listOverrides([_news()]),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BisoPage), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await pumpBisoScreen(
      tester,
      const NewsDetailScreen(idOrSlug: 'autumn-news'),
      overrides: _detailOverrides(_news()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BisoPage), findsOneWidget);
  });

  testWidgets('the detail speaks Norwegian under the no locale', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const NewsDetailScreen(idOrSlug: 'autumn-news'),
      locale: const Locale('no'),
      overrides: _detailOverrides(_news(body: '')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Les på biso.no'), findsOneWidget);
    expect(find.textContaining('sep'), findsWidgets);
  });

  testWidgets('Explore shows a News entry that opens /explore/news', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/explore',
      routes: [
        GoRoute(path: '/explore', builder: (_, _) => const ExploreScreen()),
        GoRoute(
          path: '/explore/news',
          builder: (_, _) => const Scaffold(body: Text('News list page')),
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
          scannerAccessProvider.overrideWith(
            () => FixedScannerAccess(const ScannerDenied()),
          ),
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

    await tester.tap(find.text('News'));
    await tester.pumpAndSettle();
    expect(find.text('News list page'), findsOneWidget);
  });
}
