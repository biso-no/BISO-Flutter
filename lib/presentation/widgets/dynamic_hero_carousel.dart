import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/campus_model.dart';
import '../../data/models/large_event_model.dart';
import '../../data/services/showcase_navigation_service.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../providers/notification/notification_provider.dart';

/// A campus cover followed by editorial showcases. Pages move only on a swipe,
/// so the cover never changes while someone is reading or using VoiceOver.
class DynamicHeroCarousel extends ConsumerStatefulWidget {
  const DynamicHeroCarousel({
    super.key,
    required this.campus,
    required this.showcaseItems,
    required this.onCampusTap,
  });
  final CampusModel campus;
  final List<LargeEventModel> showcaseItems;
  final VoidCallback onCampusTap;
  @override
  ConsumerState<DynamicHeroCarousel> createState() =>
      _DynamicHeroCarouselState();
}

class _DynamicHeroCarouselState extends ConsumerState<DynamicHeroCarousel> {
  int _page = 0;

  String get _campusImage =>
      'assets/images/campus/${switch (widget.campus.id) {
        '2' => 'bergen',
        '3' => 'trondheim',
        '4' => 'stavanger',
        _ => 'oslo',
      }}.png';

  @override
  void didUpdateWidget(DynamicHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.campus.id != widget.campus.id ||
        oldWidget.showcaseItems.length != widget.showcaseItems.length) {
      _page = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final unread = ref.watch(unreadCountProvider);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final count = widget.showcaseItems.length + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 16, 16),
            child: Row(
              children: [
                Text(
                  'BISO',
                  // The wordmark has a fixed size, like an image logo. The
                  // campus control next to it follows the user's text size.
                  textScaler: TextScaler.noScaling,
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1.5,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: widget.onCampusTap,
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(CupertinoIcons.chevron_down, size: 13),
                      label: Text(
                        widget.campus.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Badge(
                  isLabelVisible: unread > 0,
                  label: Text(unread > 9 ? '9+' : '$unread'),
                  child: IconButton(
                    tooltip: l10n.notificationsMessage,
                    onPressed: () => context.push('/notifications'),
                    icon: const Icon(CupertinoIcons.bell, size: 23),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(
            height: 330 + (scale - 1).clamp(0.0, 1.5) * 100,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: PageView.builder(
                key: ValueKey('${widget.campus.id}-$count'),
                onPageChanged: (index) => setState(() => _page = index),
                itemCount: count,
                itemBuilder: (context, index) {
                  final item = index == 0
                      ? null
                      : widget.showcaseItems[index - 1];
                  return _Cover(
                    image: item?.backgroundImageUrl,
                    asset: _campusImage,
                    title: item?.name ?? widget.campus.name,
                    subtitle:
                        item?.description ?? l10n.connectingStudentsMessage,
                    action: item?.effectiveCtaText ?? l10n.exploreCampusMessage,
                    onTap: () {
                      if (item == null) {
                        context.push('/explore/campus/${widget.campus.id}');
                      } else if (item.showcaseType == ShowcaseType.largeEvent &&
                          item.externalUrl == null) {
                        context.push('/events/large/${item.slug}', extra: item);
                      } else {
                        ShowcaseNavigationService().handleShowcaseCTA(
                          context,
                          item,
                        );
                      }
                    },
                  );
                },
              ),
            ),
          ),
        ),
        if (count > 1)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < count; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 20 : 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? AppColors.biLightBlue
                          : theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({
    this.image,
    required this.asset,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
  });
  final String? image;
  final String asset;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decodeWidth =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(400, 1600);
    Widget campusImage() => Image.asset(
      asset,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: decodeWidth,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        if (image?.isNotEmpty == true)
          CachedNetworkImage(
            imageUrl: image!,
            fit: BoxFit.cover,
            memCacheWidth: decodeWidth,
            placeholder: (_, _) => campusImage(),
            errorWidget: (_, _, _) => campusImage(),
          )
        else
          campusImage(),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00001731), Color(0xDD001731), Color(0xFF001731)],
              stops: [0.15, 0.68, 1],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.displayMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w300,
                  height: 1.03,
                  letterSpacing: -1.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.biLightBlue,
                  foregroundColor: AppColors.biNavy,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  minimumSize: const Size(44, 44),
                ),
                child: Text(
                  action,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
