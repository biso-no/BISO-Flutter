import '../../core/constants/app_constants.dart';
import 'appwrite_service.dart';

/// Supplies the bearer token `apps/api` authenticates the app with.
typedef ApiJwtProvider = Future<String?> Function();

/// Clears whatever [ApiJwtProvider] has kept, so the next call gets a new
/// token.
typedef ApiJwtInvalidator = void Function();

/// Reuses one Appwrite JWT between API calls.
///
/// Appwrite limits JWT creation to 100 per account per hour, so a token per
/// request would run out at a busy door. A token is reused for [reuseFor]
/// (Appwrite's live for 15 minutes), concurrent callers share one creation,
/// and a failed creation is never kept.
class AppwriteJwtCache {
  AppwriteJwtCache(
    this._create, {
    DateTime Function()? clock,
    this.reuseFor = const Duration(minutes: 10),
  }) : _clock = clock ?? DateTime.now;

  final Future<String> Function() _create;
  final DateTime Function() _clock;
  final Duration reuseFor;

  String? _jwt;
  DateTime? _createdAt;
  Future<String?>? _pending;
  int _generation = 0;

  /// The kept token while it is fresh, otherwise a new one; null when none
  /// could be created.
  Future<String?> call() {
    final jwt = _jwt;
    final createdAt = _createdAt;
    if (jwt != null && createdAt != null) {
      final age = _clock().difference(createdAt);
      if (!age.isNegative && age < reuseFor) return Future.value(jwt);
    }
    return _pending ??= _refresh();
  }

  /// Forgets the kept token. A creation still running is not kept either.
  void clear() {
    _generation++;
    _jwt = null;
    _createdAt = null;
    _pending = null;
  }

  Future<String?> _refresh() async {
    final generation = _generation;
    final startedAt = _clock();
    try {
      final jwt = await _create();
      if (generation == _generation) {
        _jwt = jwt;
        _createdAt = startedAt;
      }
      return jwt;
    } catch (_) {
      return null;
    } finally {
      if (generation == _generation) _pending = null;
    }
  }
}

final AppwriteJwtCache _appwriteJwtCache = AppwriteJwtCache(
  () async => (await account.createJWT()).jwt,
);

/// A short-lived Appwrite JWT for the signed-in account, or null without a
/// session. A request then goes out unauthenticated and the server's 401 is
/// what the caller shows, rather than a local guess about the session.
Future<String?> appwriteJwt() => _appwriteJwtCache();

/// Forgets the kept Appwrite JWT. Called whenever a session is created or
/// ended, so a token never outlives its account.
void clearAppwriteJwtCache() => _appwriteJwtCache.clear();

/// [path] on the `apps/api` base URL, without doubling the slash.
Uri apiUri(String path, [Map<String, String>? query]) {
  final base = AppConstants.apiBaseUrl.endsWith('/')
      ? AppConstants.apiBaseUrl.substring(0, AppConstants.apiBaseUrl.length - 1)
      : AppConstants.apiBaseUrl;
  return Uri.parse(
    '$base$path',
  ).replace(queryParameters: query == null || query.isEmpty ? null : query);
}
