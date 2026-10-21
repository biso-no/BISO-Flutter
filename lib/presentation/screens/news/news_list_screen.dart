import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/news_model.dart';
import '../../../data/services/deep_link_service.dart' show newsRouteFor;
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../../providers/news/news_provider.dart';
import '../../../providers/ui/locale_provider.dart';
import '../../widgets/biso/biso.dart';

const _thumbSize = 56.0;

const _pageSize = 20;
const _loadMoreThreshold = 200.0;

/// Published news for the selected campus (National included), paged with
/// infinite scroll.
class NewsListScreen extends ConsumerStatefulWidget {
  const NewsListScreen({super.key});

  @override
  ConsumerState<NewsListScreen> createState() => _NewsListScreenState();
}

class _NewsListScreenState extends ConsumerState<NewsListScreen> {
  final _scrollController = ScrollController();
  final _items = <NewsModel>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _failed = false;
  String? _loadedKey;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold) {
      _loadMore();
    }
  }

  String get _campusId => ref.read(filterCampusProvider).id;
  String get _locale => ref.read(localeProvider).languageCode;

  /// Starts over when the campus or the language changed.
  void _ensureLoaded(String campusId, String locale) {
    final key = '$campusId|$locale';
    if (_loadedKey == key) return;
    _loadedKey = key;
    _items.clear();
    _loading = true;
    _loadingMore = false;
    _hasMore = true;
    _failed = false;
    Future.microtask(_reload);
  }

  Future<void> _fetch({required bool replace}) async {
    final campusId = _campusId;
    final locale = _locale;
    try {
      final page = await ref
          .read(newsServiceProvider)
          .listNews(
            campusId: campusId,
            locale: locale,
            limit: _pageSize,
            offset: replace ? 0 : _items.length,
          );
      // A page for the old campus or language must not reach the new list.
      if (!mounted || campusId != _campusId || locale != _locale) {
        if (mounted && !replace) setState(() => _loadingMore = false);
        return;
      }
      setState(() {
        if (replace) _items.clear();
        _items.addAll(page);
        _hasMore = page.length >= _pageSize;
        _loading = false;
        _loadingMore = false;
        _failed = false;
      });
    } on Object {
      if (!mounted || campusId != _campusId || locale != _locale) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _hasMore = false;
        _failed = _items.isEmpty;
      });
    }
  }

  Future<void> _reload() => _fetch(replace: true);

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _loading) return;
    setState(() => _loadingMore = true);
    await _fetch(replace: false);
  }

  void _retry() {
    setState(() {
      _loading = true;
      _failed = false;
      _hasMore = true;
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final campusId = ref.watch(filterCampusProvider).id;
    final locale = ref.watch(localeProvider).languageCode;
    _ensureLoaded(campusId, locale);
    final campusNames = {
      for (final campus
          in ref.watch(allCampusesProvider).valueOrNull ?? const [])
        campus.id: campus.name,
    };

    final List<Widget> slivers;
    if (_loading) {
      slivers = const [SliverToBoxAdapter(child: BisoSkeleton.rows())];
    } else if (_failed) {
      slivers = [
        SliverFillRemaining(
          hasScrollBody: false,
          child: BisoErrorState(onRetry: _retry),
        ),
      ];
    } else if (_items.isEmpty) {
      slivers = [
        SliverFillRemaining(
          hasScrollBody: false,
          child: BisoEmptyState(
            icon: CupertinoIcons.news,
            accent: BisoAccent.violet,
            title: l10n.nothingHereYetCheckBackSoonMessage,
          ),
        ),
      ];
    } else {
      slivers = [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.separated(
            itemCount: _items.length + (_loadingMore ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index >= _items.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final article = _items[index];
              return _NewsRow(
                article: article,
                campusName: campusNames[article.campusId],
              );
            },
          ),
        ),
      ];
    }

    return BisoPage(
      title: l10n.newsTitle,
      leading: BisoBackButton(
        onPressed: () =>
            NavigationUtils.safeGoBack(context, fallbackRoute: '/explore'),
      ),
      onRefresh: _reload,
      controller: _scrollController,
      slivers: slivers,
    );
  }
}

class _NewsRow extends StatelessWidget {
  const _NewsRow({required this.article, this.campusName});

  final NewsModel article;
  final String? campusName;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat.yMMMd(
      Localizations.localeOf(context).languageCode,
    ).format(article.publishedAt.toLocal());
    return BisoListRow(
      leading: _Thumb(url: article.image),
      title: article.title,
      subtitle: [date, ?campusName].join(' · '),
      onTap: () => context.push(newsRouteFor(article.id)),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final placeholder = ColoredBox(
      color: palette.surfaceRaised,
      child: Icon(CupertinoIcons.news, size: 24, color: palette.muted),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: _thumbSize,
        height: _thumbSize,
        child: url?.isNotEmpty == true
            ? CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                memCacheWidth: 200,
                placeholder: (_, _) => placeholder,
                errorWidget: (_, _, _) => placeholder,
              )
            : placeholder,
      ),
    );
  }
}
