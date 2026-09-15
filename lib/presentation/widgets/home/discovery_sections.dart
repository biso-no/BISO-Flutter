import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/biso_colors.dart';
import '../../../data/models/event_model.dart';
import '../../../data/models/webshop_product_model.dart';
import '../../../data/models/job_model.dart';
import '../premium/premium_html_renderer.dart';

class BisoEventCarousel extends StatelessWidget {
  final List<EventModel> events;
  const BisoEventCarousel({super.key, required this.events});
  @override
  Widget build(BuildContext context) => SizedBox(
    height:
        213 +
        _scaledLineHeight(context, Theme.of(context).textTheme.labelLarge) * 2 +
        MediaQuery.textScalerOf(context).scale(21) * 1.2 * 2 +
        _scaledLineHeight(context, Theme.of(context).textTheme.bodyMedium),
    child: ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      scrollDirection: Axis.horizontal,
      itemCount: events.length,
      separatorBuilder: (_, _) => const SizedBox(width: 16),
      itemBuilder: (context, index) {
        final event = events[index];
        final theme = Theme.of(context);
        final palette = BisoPalette.of(context);
        return SizedBox(
          width: (MediaQuery.sizeOf(context).width - 72).clamp(240, 340),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => context.go('/explore/events'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: _FeedImage(
                      url: event.images.firstOrNull,
                      height: 180,
                      fallback: CupertinoIcons.calendar,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    DateFormat.MMMEd(
                      Localizations.localeOf(context).languageCode,
                    ).format(event.startDate.toLocal()),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: palette.link,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    event.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 21,
                      height: 1.2,
                    ),
                  ),
                  if (event.location?.isNotEmpty == true) ...[
                    const SizedBox(height: 6),
                    Text(
                      event.location!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: palette.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class BisoWebshopCarousel extends StatelessWidget {
  final List<WebshopProduct> products;
  const BisoWebshopCarousel({super.key, required this.products});
  @override
  Widget build(BuildContext context) => SizedBox(
    height:
        199 +
        MediaQuery.textScalerOf(context).scale(16) * 1.2 * 2 +
        _scaledLineHeight(context, Theme.of(context).textTheme.labelLarge) * 2,
    child: ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      scrollDirection: Axis.horizontal,
      itemCount: products.length,
      separatorBuilder: (_, _) => const SizedBox(width: 16),
      itemBuilder: (context, index) {
        final product = products[index];
        final theme = Theme.of(context);
        return SizedBox(
          width: 180,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => context.pushNamed(
                'webshop-product-detail',
                pathParameters: {'productId': product.id},
                extra: product,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: _FeedImage(
                      url: product.images.firstOrNull,
                      height: 174,
                      fallback: CupertinoIcons.bag,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    product.title ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(height: 1.2),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    NumberFormat.currency(
                      locale: Localizations.localeOf(context).toString(),
                      symbol: 'NOK',
                      decimalDigits: 0,
                    ).format(product.regularPrice),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
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

class BisoJobList extends StatelessWidget {
  final List<JobModel> jobs;
  const BisoJobList({super.key, required this.jobs});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < jobs.length; i++) ...[
              if (i > 0)
                Divider(indent: 20, endIndent: 20, color: palette.hairline),
              InkWell(
                onTap: () => context.go(
                  '/explore/volunteer',
                  extra: {'openJobId': jobs[i].id},
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            jobs[i].title.toCompactHtml(
                              style: theme.textTheme.titleMedium,
                              maxLines: 2,
                              fontSize: 17,
                            ),
                            if (jobs[i].description.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              jobs[i].description.toCompactHtml(
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: palette.muted,
                                ),
                                maxLines: 2,
                                fontSize: 14,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Icon(CupertinoIcons.chevron_right, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeedImage extends StatelessWidget {
  const _FeedImage({this.url, required this.height, required this.fallback});
  final String? url;
  final double height;
  final IconData fallback;
  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    Widget placeholder() => ColoredBox(
      color: palette.surfaceRaised,
      child: Center(child: Icon(fallback, size: 32, color: palette.muted)),
    );
    return SizedBox(
      height: height,
      width: double.infinity,
      child: url?.isNotEmpty == true
          ? CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              memCacheWidth: 1000,
              placeholder: (_, _) => placeholder(),
              errorWidget: (_, _, _) => placeholder(),
            )
          : placeholder(),
    );
  }
}

// Reserve the actual scaled line boxes so long localized copy can grow without
// clipping. Keep the horizontal lists lazy and image decode sizes bounded.
double _scaledLineHeight(BuildContext context, TextStyle? style) =>
    MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 14) *
    (style?.height ?? 1.4);
