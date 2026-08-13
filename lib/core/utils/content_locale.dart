import 'package:shared_preferences/shared_preferences.dart';

/// Resolves the locale used for BISO Sites content requests.
///
/// Mirrors the app locale persisted by `LocaleNotifier` under the
/// `language` preference key. Falls back to English.
class ContentLocale {
  const ContentLocale._();

  static Future<String> current() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString('language');
      return code == 'no' ? 'no' : 'en';
    } catch (_) {
      return 'en';
    }
  }
}
