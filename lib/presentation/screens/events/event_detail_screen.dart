import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/event_model.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/events/event_rsvp_provider.dart';
import '../../../providers/events/events_provider.dart';
import '../../widgets/biso/biso.dart';
import '../../widgets/event/event_detail_body.dart';

/// One event, reached from the list, the home carousel, a push notification
/// or a link. [idOrSlug] may be the row id or the slug.
class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.idOrSlug});

  final String idOrSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final detail = ref.watch(eventDetailProvider(idOrSlug));

    return BisoPage(
      title: l10n.eventsMessage,
      largeTitle: false,
      leading: BisoBackButton(
        onPressed: () => NavigationUtils.safeGoBack(
          context,
          fallbackRoute: '/explore/events',
        ),
      ),
      onRefresh: () async {
        final event = await ref.refresh(eventDetailProvider(idOrSlug).future);
        if (event == null || event.isCompleted || event.isCancelled) return;
        await ref.read(eventRsvpProvider(event.id).notifier).refresh();
      },
      slivers: detail.when(
        loading: () => const [SliverToBoxAdapter(child: BisoSkeleton.card())],
        error: (_, _) => [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoErrorState(
              onRetry: () => ref.invalidate(eventDetailProvider(idOrSlug)),
            ),
          ),
        ],
        data: (event) => event == null
            ? [
                SliverFillRemaining(
                  hasScrollBody: false,
                  // Members-only events are readable by everyone, so a
                  // missing one is a draft, deleted, or a bad link.
                  child: BisoEmptyState(
                    icon: CupertinoIcons.calendar,
                    accent: BisoAccent.blue,
                    title: l10n.eventNotAvailable,
                  ),
                ),
              ]
            : _eventSlivers(context, event),
      ),
    );
  }

  List<Widget> _eventSlivers(BuildContext context, EventModel event) {
    final palette = BisoPalette.of(context);
    return [
      if (event.images.isNotEmpty)
        SliverToBoxAdapter(
          child: SizedBox(
            height: 220,
            width: double.infinity,
            child: CachedNetworkImage(
              imageUrl: event.images.first,
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
        sliver: SliverToBoxAdapter(child: EventDetailBody(event: event)),
      ),
    ];
  }
}
