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
///
/// Rebuilds, and rereads, when the student changes. Each build keeps its
/// student and items in its own [_OpenedItemsStore], so a read or write still
/// running for the previous student can never reach the next one.
class InboxOpenedItemsNotifier extends Notifier<InboxOpenedItems> {
  InboxOpenedItemsNotifier({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefs;

  late _OpenedItemsStore _store;

  @override
  InboxOpenedItems build() {
    final userId = ref.watch(inboxOpenedItemsUserIdProvider);
    final store = _store = _OpenedItemsStore(userId);
    // Set as soon as the student changes, before any rebuild.
    ref.onDispose(() => store.disposed = true);
    store.loaded = _load(store);
    return const InboxOpenedItems();
  }

  /// Completes once the stored items have been read.
  Future<void> get loaded => _store.loaded;

  /// The ids of the items opened in [announcementId].
  Set<String> openedFor(String announcementId) =>
      state.openedFor(announcementId);

  /// Remembers that [itemId] of [announcementId] was opened.
  Future<void> markOpened(String announcementId, String itemId) async {
    final store = _store;
    await store.loaded;
    final opened = store.opened;
    final items = opened.remove(announcementId) ?? <String>{};
    items.add(itemId);
    opened[announcementId] = items;
    while (opened.length > kInboxOpenedItemsLimit) {
      opened.remove(opened.keys.first);
    }
    _publish(store);
    await _save(store);
  }

  Future<void> _load(_OpenedItemsStore store) async {
    final userId = store.userId;
    if (userId == null || userId.isEmpty) return;
    try {
      final raw = (await _prefs()).getString(_key(userId));
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final MapEntry(:key, :value) in decoded.entries) {
        if (key is! String || value is! List) continue;
        store.opened[key] = value.whereType<String>().toSet();
      }
      _publish(store);
    } catch (e) {
      logPrint('Inbox opened items could not be read: $e');
    }
  }

  Future<void> _save(_OpenedItemsStore store) async {
    final userId = store.userId;
    if (userId == null || userId.isEmpty) return;
    try {
      await (await _prefs()).setString(
        _key(userId),
        jsonEncode({
          for (final MapEntry(:key, :value) in store.opened.entries)
            key: value.toList(),
        }),
      );
    } catch (e) {
      logPrint('Inbox opened items could not be saved: $e');
    }
  }

  /// Shows [store]'s items, unless the build it belongs to is gone. The
  /// student is compared too: this provider is invalidated only once
  /// [inboxOpenedItemsUserIdProvider] recomputes, which can be a frame after
  /// the sign-in that changed it.
  void _publish(_OpenedItemsStore store) {
    if (store.disposed ||
        !ref.mounted ||
        ref.read(inboxOpenedItemsUserIdProvider) != store.userId) {
      return;
    }
    state = InboxOpenedItems({
      for (final MapEntry(:key, :value) in store.opened.entries)
        key: Set.unmodifiable(value),
    });
  }
}

/// One build's student and opened items.
class _OpenedItemsStore {
  _OpenedItemsStore(this.userId);

  final String? userId;

  /// The source of the state. Literal maps and sets keep insertion order, so
  /// the least recently touched announcement comes first.
  final Map<String, Set<String>> opened = {};

  late Future<void> loaded;

  /// Whether the build this store belongs to has been invalidated.
  bool disposed = false;
}

/// Whose opened items these are: the signed-in student, or null. Separate so
/// tests can pin a student.
final inboxOpenedItemsUserIdProvider = Provider<String?>(
  (ref) => ref.watch(authStateProvider.select((state) => state.signedInUserId)),
);

/// The signed-in student's opened burst items. Rebuilds, and rereads, when
/// the student changes, so one student's opened items never show for another.
final inboxOpenedItemsProvider =
    NotifierProvider<InboxOpenedItemsNotifier, InboxOpenedItems>(
      InboxOpenedItemsNotifier.new,
    );
