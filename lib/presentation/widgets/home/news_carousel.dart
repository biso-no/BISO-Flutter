import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/biso_colors.dart';
import '../../../data/models/news_model.dart';
import '../../../data/services/deep_link_service.dart' show newsRouteFor;
import 'feed_image.dart';

/// Horizontal carousel of news articles, styled like the event carousel.
class BisoNewsCarousel extends StatelessWidget {
  const BisoNewsCarousel({super.key, required this.news});

  final List<NewsModel> news;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final textTheme = Theme.of(context).textTheme;
    double line(TextStyle? style) =>
        scaler.scale(style?.fontSize ?? 14) * (style?.height ?? 1.4);
    return SizedBox(
      height: 213 + line(textTheme.labelLarge) * 2 + scaler.scale(21) * 1.2 * 2,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        scrollDirection: Axis.horizontal,
        itemCount: news.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final article = news[index];
          final palette = BisoPalette.of(context);
          return SizedBox(
            width: (MediaQuery.sizeOf(context).width - 72).clamp(240, 340),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => context.push(newsRouteFor(article.id)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BisoFeedImage(
                        url: article.image,
                        height: 180,
                        fallback: CupertinoIcons.news,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      DateFormat.MMMEd(
                        Localizations.localeOf(context).languageCode,
                      ).format(article.publishedAt.toLocal()),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelLarge?.copyWith(
                        color: palette.link,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      article.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleLarge?.copyWith(
                        fontSize: 21,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
