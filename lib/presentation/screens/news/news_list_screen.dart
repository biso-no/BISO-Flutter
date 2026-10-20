import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/news_model.dart';
import '../../../data/services/deep_link_service.dart' show newsRouteFor;
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../../providers/news/news_provider.dart';
import '../../widgets/biso/biso.dart';

const _thumbSize = 56.0;

/// Published news for the selected campus (National included).
class NewsListScreen extends ConsumerWidget {
  const NewsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final campusId = ref.watch(filterCampusProvider).id;
    final news = ref.watch(latestNewsProvider(campusId));
    final campusNames = {
      for (final campus
          in ref.watch(allCampusesProvider).valueOrNull ?? const [])
        campus.id: campus.name,
    };

    return BisoPage(
      title: l10n.newsTitle,
      leading: BisoBackButton(
        onPressed: () =>
            NavigationUtils.safeGoBack(context, fallbackRoute: '/explore'),
      ),
      onRefresh: () => ref.refresh(latestNewsProvider(campusId).future),
      slivers: news.when(
        loading: () => const [SliverToBoxAdapter(child: BisoSkeleton.rows())],
        error: (_, _) => [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoErrorState(
              onRetry: () => ref.invalidate(latestNewsProvider(campusId)),
            ),
          ),
        ],
        data: (items) => items.isEmpty
            ? [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: BisoEmptyState(
                    icon: CupertinoIcons.news,
                    accent: BisoAccent.violet,
                    title: l10n.nothingHereYetCheckBackSoonMessage,
                  ),
                ),
              ]
            : [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _NewsRow(
                      article: items[index],
                      campusName: campusNames[items[index].campusId],
                    ),
                  ),
                ),
              ],
      ),
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
