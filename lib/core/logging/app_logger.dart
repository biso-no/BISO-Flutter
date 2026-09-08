import 'package:talker_flutter/talker_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Central logging service for BISO app
/// Provides structured logging with multiple outputs:
/// - Console (debug builds)
/// - Local storage (all builds)
/// - Future: External services (Sentry, Crashlytics, etc.)
class AppLogger {
  static late final Talker _talker;
  static bool _initialized = false;
  static String? _appVersion;

  /// Initialize the logging system
  static Future<void> initialize({bool enableConsole = kDebugMode}) async {
    if (_initialized) return;

    // Get app version information
    await _loadAppVersion();

    _talker = TalkerFlutter.init(
      logger: TalkerLogger(
        output: enableConsole ? debugOutput : silentOutput,
        formatter: _ProductionFormatter(),
      ),
      settings: TalkerSettings(
        enabled: true,
        useConsoleLogs: enableConsole,
        maxHistoryItems: 1000,
      ),
      // Observer can be added later for external services
    );

    _initialized = true;
  }

  /// Load app version information from package_info_plus
  static Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
    } catch (e) {
      _appVersion = 'unknown';
      // Log the error but don't fail initialization
      if (kDebugMode) {
        debugPrint('Failed to load app version: $e');
      }
    }
  }

  /// Get the current app version
  static String get appVersion => _appVersion ?? 'unknown';

  /// Get the Talker instance for advanced usage
  static Talker get instance => _talker;

  // MARK: - Logging Methods

  /// Whether [initialize] has completed.
  ///
  /// A log call before it would otherwise throw a `LateInitializationError`
  /// from `_talker` — which would turn "we failed to log something" into a
  /// crash, in exactly the situations (early startup, a widget test, a
  /// failure on a background isolate) where the log matters most. Every entry
  /// point below falls back to `debugPrint` instead.
  static bool get isInitialized => _initialized;

  static void _fallback(String level, String message) {
    if (kDebugMode) {
      debugPrint('[$level] $message (logger not initialized)');
    }
  }

  /// Log debug information (disabled in production)
  static void debug(
    String message, {
    Map<String, dynamic>? extra,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!kDebugMode) return;
    if (!_initialized) return _fallback('DEBUG', message);
    _talker.debug(message, _buildLogData(extra, error, stackTrace));
  }

  /// Log general information
  static void info(
    String message, {
    Map<String, dynamic>? extra,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!_initialized) return _fallback('INFO', message);
    _talker.info(message, _buildLogData(extra, error, stackTrace));
  }

  /// Log warnings
  static void warning(
    String message, {
    Map<String, dynamic>? extra,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!_initialized) return _fallback('WARNING', message);
    _talker.warning(message, _buildLogData(extra, error, stackTrace));
  }

  /// Log errors
  static void error(
    String message, {
    Map<String, dynamic>? extra,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!_initialized) return _fallback('ERROR', message);
    _talker.error(message, _buildLogData(extra, error, stackTrace));
  }

  /// Log critical failures
  static void fatal(
    String message, {
    Map<String, dynamic>? extra,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!_initialized) return _fallback('FATAL', message);
    _talker.critical(message, _buildLogData(extra, error, stackTrace));
  }

  // MARK: - Feature-specific logging

  /// Log authentication events
  static void auth(
    String message, {
    String? userId,
    String? action,
    Map<String, dynamic>? extra,
  }) {
    info(
      '[AUTH] $message',
      extra: {
        'feature': 'auth',
        'user_id': userId,
        'action': action,
        ...?extra,
      },
    );
  }

  /// Log chat events
  static void chat(
    String message, {
    String? chatId,
    String? userId,
    String? action,
    Map<String, dynamic>? extra,
  }) {
    info(
      '[CHAT] $message',
      extra: {
        'feature': 'chat',
        'chat_id': chatId,
        'user_id': userId,
        'action': action,
        ...?extra,
      },
    );
  }

  /// Log expense events
  static void expense(
    String message, {
    String? expenseId,
    String? userId,
    String? action,
    Map<String, dynamic>? extra,
  }) {
    info(
      '[EXPENSE] $message',
      extra: {
        'feature': 'expense',
        'expense_id': expenseId,
        'user_id': userId,
        'action': action,
        ...?extra,
      },
    );
  }

  /// Log API calls
  static void api(
    String message, {
    String? endpoint,
    String? method,
    int? statusCode,
    Map<String, dynamic>? extra,
  }) {
    info(
      '[API] $message',
      extra: {
        'feature': 'api',
        'endpoint': endpoint,
        'method': method,
        'status_code': statusCode,
        ...?extra,
      },
    );
  }

  // MARK: - Private helpers

  static Map<String, dynamic>? _buildLogData(
    Map<String, dynamic>? extra,
    Object? error,
    StackTrace? stackTrace,
  ) {
    if (extra == null && error == null && stackTrace == null) return null;

    return {
      'timestamp': DateTime.now().toIso8601String(),
      'app_version': appVersion,
      'platform': defaultTargetPlatform.name,
      if (extra != null) ...extra,
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stack_trace': stackTrace.toString(),
    };
  }

  static void debugOutput(String message) {
    debugPrint(message);
  }

  static void silentOutput(String message) {
    // No output in production
  }
}

/// Custom formatter for production logs
class _ProductionFormatter extends LoggerFormatter {
  @override
  String fmt(LogDetails details, TalkerLoggerSettings settings) {
    final time = DateTime.now().toIso8601String();
    final level = 'LOG';
    final message = details.message?.toString() ?? '';

    return '[$time] [$level] $message';
  }
}

/// Future: External service observer (Sentry, Crashlytics, etc.)
/// Can be added when needed:
///
/// class ExternalObserver extends TalkerObserver {
///   @override
///   void onError(TalkerError err) {
///     // Send to external service
///   }
/// }
