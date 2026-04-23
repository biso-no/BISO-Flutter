import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../models/app_config.dart';

class AppConfigService {
  static const _cacheKey = 'app_config_cache';
  static const _cacheTimestampKey = 'app_config_cache_ts';
  static const _cacheTtl = Duration(hours: 1);

  Future<AppConfig> getConfig() async {
    try {
      final response = await http
          .get(Uri.parse('${AppConstants.apiBaseUrl}/api/config'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final config = AppConfig.fromJson(json);
        await _writeCache(config);
        return config;
      }
    } catch (_) {
      // fall through to cache
    }

    final cached = await _readCache();
    return cached ?? const AppConfig();
  }

  Future<void> _writeCache(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, config.toJsonString());
    await prefs.setInt(
      _cacheTimestampKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<AppConfig?> _readCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    final ts = prefs.getInt(_cacheTimestampKey);
    if (raw == null || ts == null) return null;

    final age = DateTime.now().millisecondsSinceEpoch - ts;
    if (age > _cacheTtl.inMilliseconds) return null;

    try {
      return AppConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
