import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/news_model.dart';
import '../../../providers/news/news_provider.dart';
import '../../widgets/premium/premium_html_renderer.dart';

class NewsDetailScreen extends ConsumerWidget {
  final String newsId;
  final NewsModel? article;

  const NewsDetailScreen({super.key, required this.newsId, this.article});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (article != null) {
      return _NewsDetailBody(article: article!);
    }

    // Deep link path: resolve the article by id.
    final articleAsync = ref.watch(newsItemProvider(newsId));
    return articleAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Could not load article')),
      ),
      data: (resolved) {
        if (resolved == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Article not found')),
          );
        }
        return _NewsDetailBody(article: resolved);
      },
    );
  }
}

class _NewsDetailBody extends StatelessWidget {
  final NewsModel article;

  const _NewsDetailBody({required this.article});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = article.createdAt;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/explore/news');
            }
          },
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          if (article.url.isNotEmpty)
            IconButton(
              tooltip: 'Open on biso.no',
              onPressed: () => launchUrl(
                Uri.parse(article.url),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_browser),
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (article.image != null && article.image!.isNotEmpty)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedNetworkImage(
                imageUrl: article.image!,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => Container(
                  color: AppColors.surfaceVariant,
                  child: const Icon(Icons.image_not_supported),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (article.departmentName != null ||
                    article.campusName != null)
                  Text(
                    article.departmentName ?? article.campusName!,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AppColors.defaultBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  article.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (article.author != null &&
                        article.author!.isNotEmpty) ...[
                      const Icon(
                        Icons.person_outline,
                        size: 16,
                        color: AppColors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        article.author!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                    if (date != null)
                      Text(
                        DateFormat('MMMM dd, yyyy').format(date),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                const Divider(height: 32),
                article.content.toFullHtml(
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                  fontSize: 16,
                ),
                if (article.externalUrl != null &&
                    article.externalUrl!.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(article.externalUrl!),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.link),
                    label: const Text('Read more'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
