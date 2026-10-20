import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/print_migration.dart';
import '../auth/auth_provider.dart';

/// How many announcements' opened items are kept; the least recently touched
/// go first.
const int kInboxOpenedItemsLimit = 200;

String _key(String userId) => 'inbox_opened_items_$userId';

/// Which items of each burst announcement the student has opened, by
/// announcement id.
class InboxOpenedItems {
  const InboxOpenedItems([this._byAnnouncement = const {}]);

  final Map<String, Set<String>> _byAnnouncement;

  /// The ids of the items opened in [announcementId].
  Set<String> openedFor(String announcementId) =>
      _byAnnouncement[announcementId] ?? const {};
}

/// Remembers, per signed-in student and on this device, which burst items
/// they opened from the inbox, so an opened card can leave its group.
///
/// Stored in SharedPreferences under `inbox_opened_items_<userId>` as JSON
/// `{announcementId: [itemId, …]}`, ordered from least to most recently
/// touched and capped at [kInboxOpenedItemsLimit] announcements. Signed out,
/// nothing is stored.
class InboxOpenedItemsNotifier extends StateNotifier<InboxOpenedItems> {
  InboxOpenedItemsNotifier({
    required String? userId,
    Future<SharedPreferences> Function()? prefs,
  }) : _userId = userId,
       _prefs = prefs ?? SharedPreferences.getInstance,
       super(const InboxOpenedItems()) {
    loaded = _load();
  }

  final String? _userId;
  final Future<SharedPreferences> Function() _prefs;

  /// The source of [state]. Literal maps and sets keep insertion order, so
  /// the least recently touched announcement comes first.
  final Map<String, Set<String>> _opened = {};

  /// Completes once the stored items have been read.
  late final Future<void> loaded;

  /// The ids of the items opened in [announcementId].
  Set<String> openedFor(String announcementId) =>
      state.openedFor(announcementId);

  /// Remembers that [itemId] of [announcementId] was opened.
  Future<void> markOpened(String announcementId, String itemId) async {
    await loaded;
    final items = _opened.remove(announcementId) ?? <String>{};
    items.add(itemId);
    _opened[announcementId] = items;
    while (_opened.length > kInboxOpenedItemsLimit) {
      _opened.remove(_opened.keys.first);
    }
    _publish();
    await _save();
  }

  Future<void> _load() async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return;
    try {
      final raw = (await _prefs()).getString(_key(userId));
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final MapEntry(:key, :value) in decoded.entries) {
        if (key is! String || value is! List) continue;
        _opened[key] = value.whereType<String>().toSet();
      }
      _publish();
    } catch (e) {
      logPrint('Inbox opened items could not be read: $e');
    }
  }

  Future<void> _save() async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return;
    try {
      await (await _prefs()).setString(
        _key(userId),
        jsonEncode({
          for (final MapEntry(:key, :value) in _opened.entries)
            key: value.toList(),
        }),
      );
    } catch (e) {
      logPrint('Inbox opened items could not be saved: $e');
    }
  }

  void _publish() {
    if (!mounted) return;
    state = InboxOpenedItems({
      for (final MapEntry(:key, :value) in _opened.entries)
        key: Set.unmodifiable(value),
    });
  }
}

/// The signed-in student's opened burst items. Rebuilds, and rereads, when
/// the student changes, so one student's opened items never show for another.
final inboxOpenedItemsProvider =
    StateNotifierProvider<InboxOpenedItemsNotifier, InboxOpenedItems>((ref) {
      final userId = ref.watch(
        authStateProvider.select((state) => state.signedInUserId),
      );
      return InboxOpenedItemsNotifier(userId: userId);
    });
