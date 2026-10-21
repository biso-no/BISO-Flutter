import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/weather_model.dart';

/// Configuration options for the weather API
class WeatherOptions {
  final double latitude;
  final double longitude;
  final double altitude;
  final String userAgent;
  final String? locationName;

  const WeatherOptions({
    required this.latitude,
    required this.longitude,
    this.altitude = 0,
    required this.userAgent,
    this.locationName,
  });
}

/// Service for fetching weather data from MET Norway Locationforecast API
class WeatherService {
  static const String _baseUrl =
      'https://api.met.no/weatherapi/locationforecast/2.0/compact';
  static const String _defaultUserAgent =
      'BISO-Flutter-App/1.0 (https://biso.no/)';

  /// Fetches current weather data from the MET Norway Locationforecast API
  ///
  /// [options] Configuration options including coordinates and user agent
  /// Returns weather data or throws an exception on error
  static Future<WeatherModel> getCurrentWeather(WeatherOptions options) async {
    // Ensure coordinates are properly formatted (max 4 decimals as per API requirements)
    final lat = double.parse(options.latitude.toStringAsFixed(4));
    final lon = double.parse(options.longitude.toStringAsFixed(4));
    final alt = options.altitude.round();

    // Construct the API URL
    final url = Uri.parse('$_baseUrl?lat=$lat&lon=$lon&altitude=$alt');

    try {
      // Make the API request with proper headers
      final response = await http.get(
        url,
        headers: {'User-Agent': options.userAgent},
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body) as Map<String, dynamic>;

        return WeatherModel.fromJson(
          jsonData,
          latitude: lat,
          longitude: lon,
          altitude: alt.toDouble(),
          locationName: options.locationName,
          headers: response.headers,
        );
      } else {
        _handleApiError(response.statusCode, response.reasonPhrase);
      }
    } catch (e) {
      if (e is WeatherException) {
        rethrow;
      }
      throw WeatherException('Network error: $e');
    }

    throw WeatherException('Unexpected error occurred');
  }

  /// Fetches weather data for a specific campus
  ///
  /// [campus] The campus to fetch weather for
  /// [userAgent] User agent string for the API request (optional)
  /// Returns weather data for the campus
  static Future<WeatherModel> getCampusWeather(
    Campus campus, {
    String? userAgent,
  }) async {
    final coordinates = CampusCoordinates.getCoordinates(campus);

    if (coordinates == null) {
      throw WeatherException('Unknown campus: ${campus.displayName}');
    }

    return getCurrentWeather(
      WeatherOptions(
        latitude: coordinates.latitude,
        longitude: coordinates.longitude,
        altitude: coordinates.altitude,
        userAgent: userAgent ?? _defaultUserAgent,
        locationName: campus.displayName,
      ),
    );
  }

  /// Fetches weather data for a campus by name
  ///
  /// [campusName] The name of the campus (Oslo, Bergen, Trondheim, Stavanger)
  /// [userAgent] User agent string for the API request (optional)
  /// Returns weather data for the campus
  static Future<WeatherModel> getCampusWeatherByName(
    String campusName, {
    String? userAgent,
  }) async {
    final coordinates = CampusCoordinates.getCoordinatesByName(campusName);

    if (coordinates == null) {
      throw WeatherException('Unknown campus: $campusName');
    }

    return getCurrentWeather(
      WeatherOptions(
        latitude: coordinates.latitude,
        longitude: coordinates.longitude,
        altitude: coordinates.altitude,
        userAgent: userAgent ?? _defaultUserAgent,
        locationName: campusName,
      ),
    );
  }

  /// Handles API error responses
  static void _handleApiError(int statusCode, String? reasonPhrase) {
    switch (statusCode) {
      case 403:
        throw WeatherException(
          'Access forbidden. Check your User-Agent header.',
        );
      case 429:
        throw WeatherException(
          'Too many requests. Please reduce your request frequency.',
        );
      default:
        throw WeatherException(
          'API error: $statusCode ${reasonPhrase ?? 'Unknown error'}',
        );
    }
  }
}

/// Custom exception for weather-related errors
class WeatherException implements Exception {
  final String message;

  const WeatherException(this.message);

  @override
  String toString() => 'WeatherException: $message';
}

/// Cache for weather data to avoid excessive API calls
class WeatherCache {
  static final Map<String, _CacheEntry> _cache = {};
  static const Duration _cacheTimeout = Duration(minutes: 30);

  /// Get cached weather data if available and not expired
  static WeatherModel? getCached(String cacheKey) {
    final entry = _cache[cacheKey];
    if (entry != null && DateTime.now().isBefore(entry.expiresAt)) {
      return entry.data;
    }
    return null;
  }

  /// Cache weather data
  static void cache(String cacheKey, WeatherModel data) {
    _cache[cacheKey] = _CacheEntry(
      data: data,
      expiresAt: DateTime.now().add(_cacheTimeout),
    );
  }

  /// Clear expired cache entries
  static void clearExpired() {
    final now = DateTime.now();
    _cache.removeWhere((key, entry) => now.isAfter(entry.expiresAt));
  }

  /// Clear all cache entries
  static void clearAll() {
    _cache.clear();
  }

  /// Generate cache key for a location
  static String generateCacheKey(double lat, double lon) {
    return '${lat.toStringAsFixed(4)}_${lon.toStringAsFixed(4)}';
  }
}

class _CacheEntry {
  final WeatherModel data;
  final DateTime expiresAt;

  _CacheEntry({required this.data, required this.expiresAt});
}
