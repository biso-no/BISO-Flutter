import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../data/models/app_notification_model.dart';
import '../../../data/models/inbox_item.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../widgets/biso/biso.dart';

const double kInboxThumbSize = 46;
const int _maxMiniCards = 3;

/// Divider inset that lines up with the row text after a thumbnail.
const double kInboxThumbDividerIndent = 16 + kInboxThumbSize + 12;

BisoAccent _accentFor(String? type) => switch (type) {
  'event' => BisoAccent.blue,
  'news' => BisoAccent.violet,
  'job' => BisoAccent.teal,
  _ => BisoAccent.neutral,
};

IconData _iconFor(String? type) => switch (type) {
  'event' => CupertinoIcons.calendar,
  'news' => CupertinoIcons.news,
  'job' => CupertinoIcons.briefcase,
  _ => CupertinoIcons.bell,
};

/// The type that colours a notification's tile: its linked content type, or
/// `event` for the legacy event category.
String? _tileType(AppNotification n) =>
    n.contentType ?? (n.category == 'event' ? 'event' : null);

String _categoryLabel(AppLocalizations l10n, AppNotification n) {
  if (n.isUrgent) return l10n.inboxCategoryUrgent;
  switch (_tileType(n)) {
    case 'event':
      return l10n.inboxCategoryEvent;
    case 'news':
      return l10n.inboxCategoryNews;
    case 'job':
      return l10n.inboxCategoryJob;
  }
  return n.category == 'trip'
      ? l10n.inboxCategoryTrip
      : l10n.inboxCategoryGeneral;
}

String inboxRelativeTime(AppLocalizations l10n, DateTime date, DateTime now) {
  final diff = now.difference(date);
  if (diff.inSeconds < 60) return l10n.inboxJustNow;
  if (diff.inMinutes < 60) return l10n.inboxMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.inboxHoursAgo(diff.inHours);
  if (diff.inDays < 7) return l10n.inboxDaysAgo(diff.inDays);
  if (diff.inDays < 30) return l10n.inboxWeeksAgo((diff.inDays / 7).floor());
  if (diff.inDays < 365) {
    return l10n.inboxMonthsAgo((diff.inDays / 30).floor());
  }
  return l10n.inboxYearsAgo((diff.inDays / 365).floor());
}

class InboxThumb extends StatelessWidget {
  const InboxThumb({
    super.key,
    required this.url,
    required this.size,
    required this.fallback,
    this.radius = 12,
  });

  final String? url;
  final double size;
  final IconData fallback;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    Widget placeholder() => ColoredBox(
      color: palette.surfaceRaised,
      child: Center(
        child: Icon(fallback, size: size * 0.4, color: palette.muted),
      ),
    );
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox.square(
          dimension: size,
          child: url?.isNotEmpty == true
              ? CachedNetworkImage(
                  imageUrl: url!,
                  fit: BoxFit.cover,
                  memCacheWidth: 200,
                  placeholder: (_, _) => placeholder(),
                  errorWidget: (_, _, _) => placeholder(),
                )
              : placeholder(),
        ),
      ),
    );
  }
}

class _UrgentTile extends StatelessWidget {
  const _UrgentTile();

  @override
  Widget build(BuildContext context) {
    const size = 32.0;
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: BisoPalette.of(context).error,
          borderRadius: BorderRadius.circular(size / 4),
        ),
        child: const SizedBox.square(
          dimension: size,
          child: Icon(
            CupertinoIcons.exclamationmark_triangle,
            size: size * 0.625,
            color: Color(0xFFFFFFFF),
          ),
        ),
      ),
    );
  }
}

/// One inbox row. A burst also shows a strip of its first items.
class InboxRow extends StatelessWidget {
  const InboxRow({
    super.key,
    required this.notification,
    required this.now,
    required this.onTap,
    required this.onOpenItem,
    required this.onSeeAll,
  });

  final AppNotification notification;
  final DateTime now;
  final VoidCallback onTap;
  final ValueChanged<InboxItem> onOpenItem;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = BisoPalette.of(context);
    final n = notification;
    final type = _tileType(n);

    final Widget tile;
    if (n.isUrgent) {
      tile = const _UrgentTile();
    } else if (n.image != null && n.image!.isNotEmpty) {
      tile = InboxThumb(
        url: n.image,
        size: kInboxThumbSize,
        fallback: _iconFor(type),
      );
    } else {
      tile = BisoIconTile(icon: _iconFor(type), accent: _accentFor(type));
    }

    final row = BisoListRow(
      // The tile's icon is decorative; the category word is kept for
      // screen readers.
      leading: Semantics(label: _categoryLabel(l10n, n), child: tile),
      title: n.title,
      subtitle: n.isBurst
          ? l10n.inboxNewCount(n.items.length)
          : (n.body.isNotEmpty ? n.body : null),
      value: inboxRelativeTime(l10n, n.createdAt, now),
      trailing: n.read
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(
                color: palette.link,
                shape: BoxShape.circle,
              ),
              child: const SizedBox(width: 8, height: 8),
            ),
      onTap: onTap,
    );

    if (!n.isBurst) return row;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        _BurstStrip(
          items: n.items.take(_maxMiniCards).toList(),
          total: n.items.length,
          onOpenItem: onOpenItem,
          onSeeAll: onSeeAll,
        ),
      ],
    );
  }
}

class _BurstStrip extends StatelessWidget {
  const _BurstStrip({
    required this.items,
    required this.total,
    required this.onOpenItem,
    required this.onSeeAll,
  });

  final List<InboxItem> items;
  final int total;
  final ValueChanged<InboxItem> onOpenItem;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 128,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) =>
                  _MiniCard(item: items[i], onTap: () => onOpenItem(items[i])),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: InkWell(
              onTap: onSeeAll,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.inboxSeeAll(total),
                      style: text.labelLarge?.copyWith(color: palette.link),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      CupertinoIcons.chevron_forward,
                      size: 13,
                      color: palette.link,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.item, required this.onTap});

  final InboxItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final date = item.date;
    return SizedBox(
      width: 140,
      child: Material(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 56,
                width: double.infinity,
                child: InboxThumb(
                  url: item.image,
                  size: 56,
                  radius: 0,
                  fallback: _iconFor(item.type),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title(locale),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelLarge?.copyWith(color: palette.ink),
                    ),
                    if (date != null)
                      Text(
                        MaterialLocalizations.of(
                          context,
                        ).formatShortDate(date.toLocal()),
                        maxLines: 1,
                        style: text.bodySmall?.copyWith(color: palette.muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row for one item of a burst, on the announcement detail screen.
class InboxItemRow extends StatelessWidget {
  const InboxItemRow({super.key, required this.item, required this.onTap});

  final InboxItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final date = item.date;
    return BisoListRow(
      leading: InboxThumb(
        url: item.image,
        size: kInboxThumbSize,
        fallback: _iconFor(item.type),
      ),
      title: item.title(locale),
      subtitle: date == null
          ? null
          : MaterialLocalizations.of(context).formatShortDate(date.toLocal()),
      onTap: onTap,
    );
  }
}
