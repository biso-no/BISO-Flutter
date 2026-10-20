import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/logging/print_migration.dart';
import '../../core/theme/biso_page.dart';

final _queryOrFragment = RegExp('[?#]');

/// [link] (a [Uri] or a location) as it may be logged: without its query or
/// fragment, where a sign-in link carries the secret that signs its holder
/// in. Debug logs end up in shared bug reports.
@visibleForTesting
String linkForLog(Object link) => link.toString().split(_queryOrFragment).first;

/// The in-app route for a `biso://membership` or `https://biso.no/app/membership`
/// link. A payment return carries `orderId` (and `cancelled=1` when the
/// student abandoned it). The status a return link carries is not passed on:
/// the screen verifies the order itself.
@visibleForTesting
String membershipRouteFor(Map<String, String> query) {
  final orderId = query['orderId'] ?? '';
  final params = <String, String>{
    if (orderId.isNotEmpty) 'orderId': orderId,
    if (query['cancelled'] == '1') 'cancelled': '1',
  };
  return Uri(
    path: '/profile/membership',
    queryParameters: params.isEmpty ? null : params,
  ).toString();
}

/// The in-app route for the sign-in link the app emails
/// (`https://biso.no/auth/verify?userId=…&secret=…`, or `biso://auth/verify`),
/// or null when [uri] is not one.
///
/// Only `/auth/verify` counts. biso.no's own sign-in returns
/// (`/auth/callback`, `/auth/oauth`) carry a userId and secret too, and
/// spending one here would sign the app in instead of the website.
@visibleForTesting
String? magicLinkRouteFor(Uri uri) {
  final isAppLink = switch (uri.scheme) {
    'biso' => uri.host == 'auth' && uri.path == '/verify',
    'https' || 'http' =>
      (uri.host == 'biso.no' || uri.host == 'www.biso.no') &&
          uri.path == '/auth/verify',
    _ => false,
  };
  final userId = uri.queryParameters['userId'];
  final secret = uri.queryParameters['secret'];
  if (!isAppLink || userId == null || secret == null) return null;
  return Uri(
    path: '/auth/verify-magic-link',
    queryParameters: {'userId': userId, 'secret': secret},
  ).toString();
}

/// The in-app route for a vacancy link: `biso://job?id=<id>`, or
/// `https://biso.no/app/jobs/<slug>`. The detail screen reads either an id or
/// a slug. Without one, the list of vacancies.
String jobRouteFor(String? idOrSlug) {
  final key = idOrSlug?.trim() ?? '';
  return key.isEmpty
      ? '/explore/volunteer'
      : '/explore/volunteer/${Uri.encodeComponent(key)}';
}

/// The in-app route for an event link: `biso://event?id=<id>`, a push
/// notification, or `https://biso.no/app/events/<slug>`. The detail screen
/// reads either an id or a slug. Without one, the list of events.
String eventRouteFor(String? idOrSlug) {
  final key = idOrSlug?.trim() ?? '';
  return key.isEmpty
      ? '/explore/events'
      : '/explore/events/${Uri.encodeComponent(key)}';
}

/// The in-app route for a news link: `biso://news?id=<id>`, a push
/// notification, or `https://biso.no/app/news/<slug>`. Without a key, the
/// list of articles.
String newsRouteFor(String? idOrSlug) {
  final key = idOrSlug?.trim() ?? '';
  return key.isEmpty
      ? '/explore/news'
      : '/explore/news/${Uri.encodeComponent(key)}';
}

/// The in-app location [uri] opens, or null when it opens no plain location.
///
/// Covers `biso://` links and `https://biso.no` universal links (with or
/// without the `/app` prefix) to an event, article, vacancy, product, the
/// shop, the membership page, an announcement or a tab. Null for a sign-in,
/// expense, chat or debug link, which each need more than a location, for a
/// link missing the id it needs, and for a link the app does not know.
///
/// [DeepLinkService] goes to this location. The inbox pushes it instead, so
/// Back returns to the inbox.
String? routeForDeepLink(Uri uri) => switch (uri.scheme) {
  'biso' => _bisoRouteFor(uri),
  'https' || 'http' => _isBisoHost(uri) ? _universalRouteFor(uri) : null,
  _ => null,
};

bool _isBisoHost(Uri uri) {
  final host = uri.host.toLowerCase();
  return host == 'biso.no' || host == 'www.biso.no';
}

/// The path segments of a universal link below its optional `/app` prefix.
List<String> _appSegments(Uri uri) {
  final segments = uri.pathSegments;
  return segments.isNotEmpty && segments.first == 'app'
      ? segments.skip(1).toList()
      : segments;
}

String? _bisoRouteFor(Uri uri) {
  final id = uri.queryParameters['id'];
  return switch (uri.host) {
    'event' => id == null ? null : eventRouteFor(id),
    'news' => newsRouteFor(id),
    'job' => jobRouteFor(id),
    'product' => id == null ? '/explore/products' : '/explore/products/$id',
    'shop' => _shopRouteFor(uri),
    'announcement' =>
      id == null || id.isEmpty
          ? null
          : '/announcements/${Uri.encodeComponent(id)}',
    'membership' => membershipRouteFor(uri.queryParameters),
    _ => null,
  };
}

String? _universalRouteFor(Uri uri) {
  // `/auth/...` is a sign-in link, which [magicLinkRouteFor] handles.
  if (uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'auth') {
    return null;
  }
  final segments = _appSegments(uri);
  if (segments.isEmpty) return '/home';
  final key = segments.length >= 2 ? segments[1] : null;
  return switch (segments.first) {
    'home' => '/home',
    'events' => eventRouteFor(key),
    'news' => newsRouteFor(key),
    'products' || 'marketplace' =>
      key == null ? '/explore/products' : '/explore/products/$key',
    'shop' => _shopUniversalRouteFor(uri, segments),
    'jobs' || 'volunteer' => jobRouteFor(key),
    'profile' => '/profile',
    'membership' => membershipRouteFor(uri.queryParameters),
    _ => null,
  };
}

/// The location of a `biso://shop/...` link, such as the post-payment return
/// from Vipps or Stripe.
///
/// `/api/checkout/return` on the website reconciles the payment and books
/// the revenue, then bounces an app checkout here as
/// `biso://shop/order?orderId=…&status=…`. The status is only a first
/// impression — the order screen verifies with the server itself, because a
/// deep link can be dropped by the browser or arrive before the provider has
/// finished settling.
String _shopRouteFor(Uri uri) {
  final path = uri.path;
  final orderId = uri.queryParameters['orderId'];
  if (path == '/order' || path == '/orders') {
    return orderId != null && orderId.isNotEmpty
        ? _orderRoute(orderId, uri.queryParameters['status'])
        : '/explore/products/orders';
  }
  if (path == '/cart') return '/explore/products/cart';
  return '/explore/products';
}

/// The same destinations over `https://biso.no/app/shop/...`, so a link
/// shared outside the app opens the same place.
String _shopUniversalRouteFor(Uri uri, List<String> segments) {
  if (segments.length >= 2 && segments[1] == 'order') {
    final id = segments.length >= 3
        ? segments[2]
        : uri.queryParameters['orderId'];
    return id != null && id.isNotEmpty
        ? _orderRoute(id, uri.queryParameters['status'])
        : '/explore/products/orders';
  }
  if (segments.length >= 2 && segments[1] == 'cart') {
    return '/explore/products/cart';
  }
  return '/explore/products';
}

String _orderRoute(String orderId, String? status) {
  final base = '/explore/products/order/${Uri.encodeComponent(orderId)}';
  return status == null || status.isEmpty
      ? base
      : '$base?status=${Uri.encodeComponent(status)}';
}

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  final List<Uri> _pendingUris = [];
  final List<String> _pendingRoutes = [];

  Future<void> initialize() async {
    _appLinks = AppLinks();

    // Handle links when app is already running
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        logPrint('🔗 Deep link received: ${linkForLog(uri)}');
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
        logPrint('🔗 Initial deep link: ${linkForLog(initialUri)}');
        _handleDeepLink(initialUri);
      }
    } catch (e) {
      logPrint('🔴 Failed to get initial link: $e');
    }
  }

  void _handleDeepLink(Uri uri) {
    logPrint('🔗 Handling deep link: ${linkForLog(uri)}');

    if (navigatorKey.currentContext == null) {
      _pendingUris.add(uri);
      logPrint(
        '🔗 Queued deep link until navigation is ready: ${linkForLog(uri)}',
      );
      return;
    }

    switch (uri.scheme) {
      case 'biso':
        _handleBisoLink(uri);
      case 'https' || 'http':
        _handleUniversalLink(uri);
      default:
        logPrint('🔴 Unknown deep link scheme: ${uri.scheme}');
    }
  }

  void _handleBisoLink(Uri uri) {
    switch (uri.host) {
      case 'auth':
        _handleAuthDeepLink(uri);
      case 'expense':
        _openExpenseRoute(uri, pathSegments: uri.pathSegments);
      case 'chat':
        _handleChatDeepLink(uri);
      case 'debug':
        if (kDebugMode) _handleDebugDeepLink(uri);
      default:
        _goToLink(uri);
    }
  }

  void _handleUniversalLink(Uri uri) {
    if (!_isBisoHost(uri)) {
      logPrint('🔴 Unknown universal link host: ${uri.host}');
      return;
    }

    final segments = uri.pathSegments;
    if (segments.isNotEmpty && segments.first == 'auth') {
      final route = magicLinkRouteFor(uri);
      if (route != null) {
        logPrint('🔗 Sign-in link universal link received');
        _go(route);
      } else {
        logPrint('ℹ️ Not the app sign-in link, ignoring: ${uri.path}');
      }
      return;
    }

    final appSegments = _appSegments(uri);
    if (appSegments.isNotEmpty &&
        (appSegments.first == 'expenses' || appSegments.first == 'expense')) {
      _openExpenseRoute(uri, pathSegments: appSegments);
      return;
    }

    _goToLink(uri);
  }

  /// Goes to the location [uri] opens (see [routeForDeepLink]).
  void _goToLink(Uri uri) {
    final route = routeForDeepLink(uri);
    if (route == null) {
      logPrint('🔴 Unhandled deep link: ${linkForLog(uri)}');
      return;
    }
    _go(route);
  }

  void _handleAuthDeepLink(Uri uri) {
    final path = uri.path;
    final queryParams = uri.queryParameters;

    logPrint('🔗 Auth deep link path: $path');
    logPrint('🔗 Auth deep link params: ${queryParams.keys.join(', ')}');

    if (path == '/magic-link' || path == '/verify') {
      final route = magicLinkRouteFor(uri.replace(path: '/verify'));
      if (route != null) {
        _go(route);
      } else {
        logPrint('🔴 Missing userId or secret in sign-in link deep link');
        _go('/auth/login');
      }
    } else {
      logPrint('🔴 Unknown auth deep link path: $path');
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
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

  /// Debug builds only: `biso://debug/open?path=/explore/products&scroll=320`
  /// opens a route with its page pre-scrolled, so each screen's header can be
  /// screenshotted from the command line with `xcrun simctl openurl`.
  void _handleDebugDeepLink(Uri uri) {
    final context = navigatorKey.currentContext;
    final path = uri.queryParameters['path'];
    if (context == null || path == null) return;
    BisoPageDebug.initialScroll.value =
        double.tryParse(uri.queryParameters['scroll'] ?? '') ?? 0;
    GoRouter.of(context).go(path);
  }

  /// Public method to handle programmatic deep links
  void handleDeepLink(Uri uri) {
    _handleDeepLink(uri);
  }

  /// Navigates to an in-app [location], or queues it until a navigator exists
  /// (a cold start from a notification tap), when [flushPendingLinks] replays it.
  void queueRoute(String location) {
    if (navigatorKey.currentContext == null) {
      _pendingRoutes.add(location);
      logPrint(
        '🔗 Queued route until navigation is ready: ${linkForLog(location)}',
      );
      return;
    }
    _go(location);
  }

  @visibleForTesting
  List<String> get pendingRoutesForTest => List.unmodifiable(_pendingRoutes);

  void flushPendingLinks() {
    if (navigatorKey.currentContext == null) return;
    if (_pendingUris.isEmpty && _pendingRoutes.isEmpty) return;
    final pending = List<Uri>.from(_pendingUris);
    final pendingRoutes = List<String>.from(_pendingRoutes);
    _pendingUris.clear();
    _pendingRoutes.clear();
    for (final uri in pending) {
      _handleDeepLink(uri);
    }
    pendingRoutes.forEach(_go);
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
      logPrint(
        '🔴 No navigation context available for deep link: '
        '${linkForLog(location)}',
      );
    }
  }
}

// Global navigator key for deep link navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
