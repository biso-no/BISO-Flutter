import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/logging/print_migration.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  final List<Uri> _pendingUris = [];

  Future<void> initialize() async {
    _appLinks = AppLinks();

    // Handle links when app is already running
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        logPrint('🔗 Deep link received: $uri');
        _handleDeepLink(uri);
      },
      onError: (Object err) {
        logPrint('🔴 Deep link error: $err');
      },
    );

    // Handle initial link when app is launched from closed state
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        logPrint('🔗 Initial deep link: $initialUri');
        _handleDeepLink(initialUri);
      }
    } catch (e) {
      logPrint('🔴 Failed to get initial link: $e');
    }
  }

  void _handleDeepLink(Uri uri) {
    logPrint('🔗 Handling deep link: ${uri.toString()}');

    if (navigatorKey.currentContext == null) {
      _pendingUris.add(uri);
      logPrint('🔗 Queued deep link until navigation is ready: $uri');
      return;
    }

    if (uri.scheme == 'biso') {
      switch (uri.host) {
        case 'auth':
          _handleAuthDeepLink(uri);
          break;
        case 'event':
          _handleEventDeepLink(uri);
          break;
        case 'product':
          _handleProductDeepLink(uri);
          break;
        case 'job':
          _handleJobDeepLink(uri);
          break;
        case 'expense':
          _handleExpenseDeepLink(uri);
          break;
        case 'chat':
          _handleChatDeepLink(uri);
          break;
        default:
          logPrint('🔴 Unknown deep link host: ${uri.host}');
      }
    } else if (uri.scheme == 'https' || uri.scheme == 'http') {
      _handleUniversalLink(uri);
    } else {
      logPrint('🔴 Unknown deep link scheme: ${uri.scheme}');
    }
  }

  void _handleUniversalLink(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host != 'biso.no' && host != 'www.biso.no') {
      logPrint('🔴 Unknown universal link host: ${uri.host}');
      return;
    }

    final segments = uri.pathSegments;
    if (segments.length >= 2 && segments.first == 'auth') {
      logPrint('ℹ️ Ignoring https auth link: ${uri.toString()}');
      return;
    }

    final appSegments = segments.isNotEmpty && segments.first == 'app'
        ? segments.skip(1).toList()
        : segments;
    if (appSegments.isEmpty) {
      _go('/home');
      return;
    }

    switch (appSegments.first) {
      case 'home':
        _go('/home');
        break;
      case 'events':
        _go('/explore/events');
        break;
      case 'products':
      case 'marketplace':
        if (appSegments.length >= 2) {
          _go('/explore/products/${appSegments[1]}');
        } else {
          _go('/explore/products');
        }
        break;
      case 'jobs':
      case 'volunteer':
        _go('/explore/volunteer');
        break;
      case 'expenses':
      case 'expense':
        _openExpenseRoute(uri, pathSegments: appSegments);
        break;
      case 'profile':
        _go('/profile');
        break;
      case 'ai':
      case 'ai-chat':
        _go('/explore/ai-chat');
        break;
      default:
        logPrint('🔴 Unknown universal link path: ${uri.path}');
    }
  }

  void _handleAuthDeepLink(Uri uri) {
    final path = uri.path;
    final queryParams = uri.queryParameters;

    logPrint('🔗 Auth deep link path: $path');
    logPrint('🔗 Auth deep link params: $queryParams');

    if (path == '/magic-link' || path == '/verify') {
      // Magic link scheme disabled (OTP-only). Do nothing.
      logPrint('ℹ️ Magic link deep links disabled. Ignoring: $uri');
    } else {
      logPrint('🔴 Unknown auth deep link path: $path');
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
  }

  /// Handle event deep links
  void _handleEventDeepLink(Uri uri) {
    final eventId = uri.queryParameters['id'];

    logPrint('🔗 Event deep link - ID: $eventId');

    if (eventId != null) {
      final context = navigatorKey.currentContext;
      if (context != null) {
        // Navigate to events screen and then open the event modal
        context.go('/explore/events', extra: {'eventId': eventId});
      } else {
        logPrint('🔴 No navigation context available for event deep link');
      }
    } else {
      logPrint('🔴 Missing event ID in deep link');
    }
  }

  /// Handle product deep links
  void _handleProductDeepLink(Uri uri) {
    final productId = uri.queryParameters['id'];

    logPrint('🔗 Product deep link - ID: $productId');

    if (productId != null) {
      _go('/explore/products/$productId');
    } else {
      _go('/explore/products');
    }
  }

  /// Handle job deep links
  void _handleJobDeepLink(Uri uri) {
    final jobId = uri.queryParameters['id'];

    logPrint('🔗 Job deep link - ID: $jobId');

    if (jobId != null) {
      final context = navigatorKey.currentContext;
      if (context != null) {
        // Navigate to jobs screen and then open the job modal
        context.go('/explore/volunteer', extra: {'openJobId': jobId});
      } else {
        logPrint('🔴 No navigation context available for job deep link');
      }
    } else {
      _go('/explore/volunteer');
    }
  }

  /// Handle expense deep links
  void _handleExpenseDeepLink(Uri uri) {
    _openExpenseRoute(uri, pathSegments: uri.pathSegments);
  }

  /// Handle chat deep links
  void _handleChatDeepLink(Uri uri) {
    final chatId = uri.queryParameters['id'];

    logPrint('🔗 Chat deep link - ID: $chatId');

    if (chatId != null) {
      final context = navigatorKey.currentContext;
      if (context != null) {
        // Navigate to chat conversation
        context.go('/chat/conversation/$chatId');
      } else {
        logPrint('🔴 No navigation context available for chat deep link');
      }
    } else {
      logPrint('🔴 Missing chat ID in deep link');
    }
  }

  /// Public method to handle programmatic deep links
  void handleDeepLink(Uri uri) {
    _handleDeepLink(uri);
  }

  void flushPendingLinks() {
    if (navigatorKey.currentContext == null || _pendingUris.isEmpty) return;
    final pending = List<Uri>.from(_pendingUris);
    _pendingUris.clear();
    for (final uri in pending) {
      _handleDeepLink(uri);
    }
  }

  void _openExpenseRoute(Uri uri, {required List<String> pathSegments}) {
    final batchId = uri.queryParameters['batch'];
    final expenseId = uri.queryParameters['id'];
    final wantsNew =
        pathSegments.contains('new') || uri.queryParameters['action'] == 'new';

    logPrint('🔗 Expense deep link - ID: $expenseId batch: $batchId');

    if (wantsNew || batchId != null) {
      final batchQuery = batchId == null || batchId.isEmpty
          ? ''
          : '?batch=${Uri.encodeComponent(batchId)}';
      _go('/explore/expenses/new$batchQuery');
      return;
    }

    final context = navigatorKey.currentContext;
    if (context != null) {
      context.go(
        '/explore/expenses',
        extra: expenseId == null ? null : {'expenseId': expenseId},
      );
    } else {
      logPrint('🔴 No navigation context available for expense deep link');
    }
  }

  void _go(String location) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      context.go(location);
    } else {
      logPrint('🔴 No navigation context available for deep link: $location');
    }
  }
}

// Global navigator key for deep link navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
