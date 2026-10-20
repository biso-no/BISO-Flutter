import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/notification_topics.dart';
import '../../core/logging/print_migration.dart';
import '../../data/services/profile_api_client.dart';
import '../auth/auth_provider.dart';
import '../ui/locale_provider.dart';

final profileApiClientProvider = Provider<ProfileApiClient>(
  (ref) => ProfileApiClient(),
);

String _syncedKey(String userId) => 'push_language_synced_$userId';

/// Tells the server which language to push in, by saving it on the profile.
///
/// Runs at launch and whenever the signed-in student or the app language
/// changes. Only runs for a student with a profile row: the server creates one
/// if it is missing. The last saved value is remembered per student so an
/// unchanged language costs no request. A failed save, or one the server
/// answers without the language, is logged and retried on the next start or
/// language change.
final pushLanguageSyncProvider = FutureProvider<void>((ref) async {
  final (ready, userId) = ref.watch(
    authStateProvider.select(
      (state) => (
        !state.isLoading && state.isAuthenticated && state.hasProfile,
        state.user?.id,
      ),
    ),
  );
  final language = pushLocaleFor(
    ref.watch(localeProvider.select((l) => l.languageCode)),
  );
  if (!ready || userId == null) return;
  // Read before any await: a language change mid-save invalidates `ref`.
  final api = ref.read(profileApiClientProvider);

  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_syncedKey(userId)) == language) return;
    final saved = await api.upsert({'locale': language});
    // An API that predates the column drops `locale` and still answers
    // success, so only a saved profile that carries it counts as synced.
    if (saved['locale'] != language) {
      logPrint('Push language not saved: the profile came back without it');
      return;
    }
    await prefs.setString(_syncedKey(userId), language);
  } catch (e) {
    logPrint('Push language sync failed: $e');
  }
});
