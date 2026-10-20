import 'package:biso/core/theme/biso_page.dart';
import 'package:biso/data/models/app_config.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/presentation/screens/explore/explore_screen.dart';
import 'package:biso/presentation/screens/news/news_detail_screen.dart';
import 'package:biso/presentation/screens/news/news_list_screen.dart';
import 'package:biso/data/models/news_model.dart';
import 'package:biso/data/services/news_service.dart';
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

  @override
  Future<List<NewsModel>> listNews({
    String? campusId,
    String locale = 'no',
    int limit = 20,
    int offset = 0,
  }) async => items;
}

List<Override> _listOverrides(List<NewsModel> items) => [
  filterCampusProvider.overrideWithValue(_campus),
  newsServiceProvider.overrideWithValue(_FakeNewsService(items)),
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

  testWidgets('a missing article for a non-member says members only', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const NewsDetailScreen(idOrSlug: 'secret'),
      overrides: _detailOverrides(null),
    );
    await tester.pumpAndSettle();

    expect(find.text('Members only'), findsOneWidget);
  });

  testWidgets('a missing article for a member says it is not available', (
    tester,
  ) async {
    await pumpBisoScreen(
      tester,
      const NewsDetailScreen(idOrSlug: 'gone'),
      overrides: _detailOverrides(null, member: true),
    );
    await tester.pumpAndSettle();

    expect(find.text("This article isn't available"), findsOneWidget);
    expect(find.text('Members only'), findsNothing);
  });

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
