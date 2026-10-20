import '../../data/models/app_notification_model.dart';

enum InboxDay { today, yesterday, thisWeek, earlier }

class InboxSection {
  final InboxDay day;
  final List<AppNotification> items;
  const InboxSection({required this.day, required this.items});
}

/// How long an unread urgent notification stays pinned to the top.
const Duration kUrgentPinWindow = Duration(days: 3);

bool _isPinned(AppNotification n, DateTime now) =>
    n.isUrgent && !n.read && now.difference(n.createdAt) <= kUrgentPinWindow;

/// Unread urgent rows sent within 3 days first, newest first; the rest keep
/// their order.
List<AppNotification> pinUrgent(List<AppNotification> items, DateTime now) {
  final pinned = items.where((n) => _isPinned(n, now)).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final rest = items.where((n) => !_isPinned(n, now));
  return [...pinned, ...rest];
}

/// Groups [items] by local calendar day relative to [now]. Pinned urgent rows
/// are left out (they render above the groups). Empty groups are omitted.
List<InboxSection> groupByDay(List<AppNotification> items, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final buckets = {for (final d in InboxDay.values) d: <AppNotification>[]};
  for (final n in items) {
    if (_isPinned(n, now)) continue;
    final t = n.createdAt.toLocal();
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    final bucket = diff <= 0
        ? InboxDay.today
        : diff == 1
        ? InboxDay.yesterday
        : diff <= 7
        ? InboxDay.thisWeek
        : InboxDay.earlier;
    buckets[bucket]!.add(n);
  }
  return [
    for (final d in InboxDay.values)
      if (buckets[d]!.isNotEmpty) InboxSection(day: d, items: buckets[d]!),
  ];
}

List<AppNotification> applyFilter(
  List<AppNotification> items,
  InboxFilter filter,
) {
  if (filter == InboxFilter.all) return items;
  return items.where((n) => n.filter == filter).toList();
}
