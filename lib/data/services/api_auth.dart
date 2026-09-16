import '../../core/constants/app_constants.dart';
import 'appwrite_service.dart';

/// Supplies the bearer token `apps/api` authenticates the app with.
typedef ApiJwtProvider = Future<String?> Function();

/// A short-lived Appwrite JWT for the signed-in account, or null without a
/// session. A request then goes out unauthenticated and the server's 401 is
/// what the caller shows, rather than a local guess about the session.
Future<String?> appwriteJwt() async {
  try {
    return (await account.createJWT()).jwt;
  } catch (_) {
    return null;
  }
}

/// [path] on the `apps/api` base URL, without doubling the slash.
Uri apiUri(String path, [Map<String, String>? query]) {
  final base = AppConstants.apiBaseUrl.endsWith('/')
      ? AppConstants.apiBaseUrl.substring(0, AppConstants.apiBaseUrl.length - 1)
      : AppConstants.apiBaseUrl;
  return Uri.parse(
    '$base$path',
  ).replace(queryParameters: query == null || query.isEmpty ? null : query);
}
