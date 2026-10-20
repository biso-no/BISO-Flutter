import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/news_model.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/membership/membership_overview_provider.dart';
import '../../../providers/news/news_provider.dart';
import '../../widgets/biso/biso.dart';
import '../../widgets/members_only_state.dart';
import '../../widgets/premium/premium_html_renderer.dart';

const _siteNewsUrl = 'https://biso.no/news';

/// One article, reached from the list, the home carousel, a push
/// notification or a link. [idOrSlug] may be the row id or the slug.
class NewsDetailScreen extends ConsumerWidget {
  const NewsDetailScreen({super.key, required this.idOrSlug});

  final String idOrSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final detail = ref.watch(newsDetailProvider(idOrSlug));

    return BisoPage(
      title: l10n.newsTitle,
      largeTitle: false,
      leading: BisoBackButton(
        onPressed: () =>
            NavigationUtils.safeGoBack(context, fallbackRoute: '/explore/news'),
      ),
      onRefresh: () => ref.refresh(newsDetailProvider(idOrSlug).future),
      slivers: detail.when(
        loading: () => const [SliverToBoxAdapter(child: BisoSkeleton.card())],
        error: (_, _) => [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoErrorState(
              onRetry: () => ref.invalidate(newsDetailProvider(idOrSlug)),
            ),
          ),
        ],
        data: (article) => article == null
            ? [
                SliverFillRemaining(
                  hasScrollBody: false,
                  // Hidden content reads as "not found" to a non-member.
                  child: ref.watch(hasValidMembershipProvider)
                      ? BisoEmptyState(
                          icon: CupertinoIcons.news,
                          accent: BisoAccent.violet,
                          title: l10n.newsNotAvailable,
                        )
                      : const MembersOnlyState(),
                ),
              ]
            : _articleSlivers(context, article),
      ),
    );
  }

  List<Widget> _articleSlivers(BuildContext context, NewsModel article) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final date = DateFormat.yMMMMd(
      Localizations.localeOf(context).languageCode,
    ).format(article.publishedAt.toLocal());
    final byline = [
      if (article.author?.trim().isNotEmpty == true) article.author!.trim(),
      date,
    ].join(' · ');
    final summary = article.shortDescription?.trim() ?? '';

    return [
      if (article.image?.isNotEmpty == true)
        SliverToBoxAdapter(
          child: SizedBox(
            height: 220,
            width: double.infinity,
            child: CachedNetworkImage(
              imageUrl: article.image!,
              fit: BoxFit.cover,
              memCacheWidth: 1080,
              errorWidget: (_, _, _) =>
                  ColoredBox(color: palette.surfaceRaised),
            ),
          ),
        ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          24,
          16,
          24,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        sliver: SliverList.list(
          children: [
            Text(article.title, style: text.headlineSmall),
            const SizedBox(height: 8),
            Text(
              byline,
              style: text.bodyMedium?.copyWith(color: palette.muted),
            ),
            const SizedBox(height: 20),
            if (article.hasRenderableBody)
              article.body.toFullHtml(style: text.bodyLarge)
            else ...[
              if (summary.isNotEmpty) Text(summary, style: text.bodyLarge),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => _openOnSite(article),
                child: Text(l10n.readOnBisoNo),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  Future<void> _openOnSite(NewsModel article) {
    final slug = article.slug?.trim() ?? '';
    final url = slug.isEmpty
        ? _siteNewsUrl
        : '$_siteNewsUrl/${Uri.encodeComponent(slug)}';
    return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
