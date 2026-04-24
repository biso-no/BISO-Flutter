import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_options.dart';
import 'core/theme/premium_theme.dart';
import 'core/logging/logging_config.dart';
import 'core/constants/app_colors.dart';
// Appwrite services are now globally initialized
import 'generated/l10n/app_localizations.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/auth/otp_verification_screen.dart';
import 'presentation/screens/onboarding/onboarding_screen.dart';
import 'presentation/screens/home/premium_home_screen.dart';
import 'presentation/screens/explore/explore_screen.dart';
import 'presentation/screens/explore/events_screen.dart';
// marketplace screen imported as alias below
import 'presentation/screens/explore/marketplace_screen.dart' as market;
import 'presentation/screens/explore/sell_product_screen.dart';
import 'presentation/screens/explore/product_detail_screen.dart';
import 'presentation/screens/explore/webshop_product_detail_screen.dart';
import 'data/models/webshop_product_model.dart';
import 'presentation/screens/explore/jobs_screen.dart';
import 'presentation/screens/explore/expenses_screen.dart';
import 'presentation/screens/explore/units_overview_screen.dart';
import 'presentation/screens/explore/unit_detail_screen.dart';
import 'presentation/screens/explore/departures_screen.dart';
import 'presentation/screens/explore/campus_detail_screen.dart';
import 'presentation/screens/ai_chat/ai_chat_screen.dart';
import 'presentation/screens/profile/profile_screen.dart';
import 'providers/auth/auth_provider.dart';
import 'providers/ui/locale_provider.dart';
import 'presentation/screens/events/large_event_screen.dart';
import 'presentation/screens/validator/controller_mode_screen.dart';
import 'data/models/large_event_model.dart';
import 'data/services/large_event_service.dart';
import 'data/services/notification_service.dart';
import 'data/services/deep_link_service.dart';
import 'providers/campus/campus_provider.dart';

// Background message handler for Firebase
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Handle background messages here if needed
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize logging system early
  await LoggingConfig.initialize();

  // Initialize Firebase
  await Firebase.initializeApp();

  // Initialize Firebase Messaging for background notifications
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize notification service
  await NotificationService().initialize();

  // Initialize deep link service (with error handling)
  try {
    await DeepLinkService().initialize();
  } catch (e) {
    debugPrint('Warning: Deep link service failed to initialize: $e');
    // Continue app startup even if deep links fail
  }

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const ProviderScope(child: BisoApp()));
}

class BisoApp extends ConsumerWidget {
  const BisoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch auth state and initialize user data when authenticated
    ref.watch(authStateProvider);
    // Ensure campus is initialized before rendering content on first launch
    final _ = ref.watch(campusInitializedProvider);
    // Start feature flag resolution at launch so shop routes do not decide
    // their initial mode from a screen-local loading state.
    ref.watch(market.marketplaceFeatureEnabledProvider);

    // Watch locale changes to update the app language
    final currentLocale = ref.watch(localeProvider);

    // Auth state listener is now handled internally by AuthProvider
    // No need for external orchestration

    return MaterialApp.router(
      title: 'BISO',
      debugShowCheckedModeBanner: false,
      theme: PremiumTheme.lightTheme,
      darkTheme: PremiumTheme.darkTheme,
      themeMode: ThemeMode.system,
      locale: currentLocale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('no')],
      routerConfig: _router,
    );
  }
}

// Create router as a static instance to prevent rebuilding
final _router = GoRouter(
  navigatorKey: navigatorKey,
  initialLocation: '/',
  routes: [
    // Auth routes (outside shell)
    GoRoute(
      path: '/auth/login',
      name: 'login',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final useFallback = extra?['useFallback'] == true;
        return LoginScreen(useFallback: useFallback);
      },
    ),
    GoRoute(
      path: '/auth/verify-otp',
      name: 'verify-otp',
      builder: (context, state) =>
          OtpVerificationScreen(email: state.extra as String? ?? ''),
    ),
    // Magic link route removed: OTP-only flow
    GoRoute(
      path: '/onboarding',
      name: 'onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),

    // Main app shell with tab navigation
    ShellRoute(
      builder: (context, state, child) {
        return _AppShell(child: child);
      },
      routes: [
        // Main tabs
        GoRoute(path: '/', redirect: (context, state) => '/home'),
        GoRoute(
          path: '/home',
          name: 'home',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: _HomePage()),
        ),
        GoRoute(
          path: '/explore',
          name: 'explore',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: _ExplorePage()),
          routes: [
            // Explore sub-routes - these will now properly return to explore tab
            GoRoute(
              path: '/events',
              name: 'events',
              builder: (context, state) => const EventsScreen(),
            ),
            GoRoute(
              path: '/departures',
              name: 'departures',
              builder: (context, state) => const DeparturesScreen(),
            ),
            GoRoute(
              path: '/products',
              name: 'products',
              builder: (context, state) => const market.MarketplaceScreen(),
              routes: [
                GoRoute(
                  path: '/new',
                  name: 'product-new',
                  builder: (context, state) => const SellProductScreen(),
                ),
                GoRoute(
                  path: '/:productId',
                  name: 'product-detail',
                  builder: (context, state) => ProductDetailScreen(
                    productId: state.pathParameters['productId']!,
                  ),
                ),
                GoRoute(
                  path: '/webshop/:productId',
                  name: 'webshop-product-detail',
                  builder: (context, state) {
                    final product = state.extra as WebshopProduct?;
                    if (product == null) {
                      // Fallback if product not passed - shouldn't happen
                      return const Scaffold(
                        body: Center(child: Text('Product not found')),
                      );
                    }
                    return WebshopProductDetailScreen(product: product);
                  },
                ),
              ],
            ),
            GoRoute(
              path: '/units',
              name: 'units',
              builder: (context, state) => const UnitsOverviewScreen(),
              routes: [
                GoRoute(
                  path: '/:id',
                  name: 'unit-detail',
                  builder: (context, state) {
                    final extra = state.extra as Map<String, dynamic>?;
                    final id = state.pathParameters['id']!;
                    final name = extra?['name'] as String? ?? 'Organization';
                    return UnitDetailScreen(
                      departmentId: id,
                      departmentName: name,
                    );
                  },
                ),
              ],
            ),
            GoRoute(
              path: '/expenses',
              name: 'expenses',
              builder: (context, state) => const ExpensesScreen(),
            ),
            GoRoute(
              path: '/volunteer',
              name: 'volunteer',
              builder: (context, state) {
                final extra = state.extra as Map<String, dynamic>?;
                final openJobId = extra != null
                    ? extra['openJobId'] as String?
                    : null;
                return JobsScreen(openJobId: openJobId);
              },
            ),
            GoRoute(
              path: '/ai-chat',
              name: 'ai-chat',
              builder: (context, state) => const AiChatScreen(),
            ),
            GoRoute(
              path: '/campus/:campusId',
              name: 'campus-detail',
              builder: (context, state) {
                final campusId = state.pathParameters['campusId']!;
                return CampusDetailScreen(campusId: campusId);
              },
            ),
          ],
        ),
        // Chat route temporarily removed from main tabs during launch
        GoRoute(
          path: '/profile',
          name: 'profile',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: _ProfilePage()),
        ),
      ],
    ),

    // Special routes (outside shell)
    GoRoute(
      path: '/events/large/:slug',
      name: 'large-event',
      builder: (context, state) {
        final extra = state.extra;
        if (extra is LargeEventModel) {
          return LargeEventScreen(event: extra);
        }
        // Deep link fallback: fetch by slug
        final slug = state.pathParameters['slug'] ?? '';
        return _LargeEventLoader(slug: slug);
      },
    ),
    GoRoute(
      path: '/controller-mode',
      name: 'controller-mode',
      builder: (context, state) => const ControllerModeScreen(),
    ),
  ],
);

// App Shell that contains the bottom navigation and manages tab state
class _AppShell extends ConsumerStatefulWidget {
  final Widget child;

  const _AppShell({required this.child});

  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell> {
  int _selectedIndex = 0;

  void _onTabChanged(int index) {
    setState(() {
      _selectedIndex = index;
    });

    // Navigate to the appropriate tab route
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/explore');
        break;
      case 2:
        context.go('/profile');
        break;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Update selected index based on current route
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/home')) {
      _selectedIndex = 0;
    } else if (location.startsWith('/explore')) {
      _selectedIndex = 1;
    } else if (location.startsWith('/profile')) {
      _selectedIndex = 2;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onTabChanged,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppColors.defaultBlue,
          unselectedItemColor: Colors.grey,
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.home_outlined),
              activeIcon: const Icon(Icons.home_rounded),
              label: l10n.homeMessage,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.explore_outlined),
              activeIcon: const Icon(Icons.explore_rounded),
              label: l10n.exploreMessage,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.person_outline_rounded),
              activeIcon: const Icon(Icons.person_rounded),
              label: l10n.profileMessage,
            ),
          ],
        ),
      ),
    );
  }
}

// Page wrapper components
class _HomePage extends StatelessWidget {
  const _HomePage();

  @override
  Widget build(BuildContext context) {
    return PremiumHomePage(
      navigateToTab: (int index) {
        switch (index) {
          case 1:
            context.go('/explore');
            break;
          case 2:
            context.go('/profile');
            break;
          default:
            context.go('/home');
            break;
        }
      },
    );
  }
}

class _ExplorePage extends StatelessWidget {
  const _ExplorePage();

  @override
  Widget build(BuildContext context) {
    return const ExploreScreen();
  }
}

// class _ChatPage removed during launch (chat disabled in bottom nav)

class _ProfilePage extends ConsumerWidget {
  const _ProfilePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final l10n = AppLocalizations.of(context)!;

    if (authState.isAuthenticated) {
      return const ProfileScreen();
    } else {
      return PremiumAuthRequiredPage(
        title: l10n.profileMessage,
        description: 'Manage your account and preferences',
        icon: Icons.person_outline_rounded,
      );
    }
  }
}

class _LargeEventLoader extends StatefulWidget {
  final String slug;
  const _LargeEventLoader({required this.slug});
  @override
  State<_LargeEventLoader> createState() => _LargeEventLoaderState();
}

class _LargeEventLoaderState extends State<_LargeEventLoader> {
  LargeEventModel? _event;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final service = LargeEventService();
      final result = await service.fetchEventBySlug(widget.slug);
      if (!mounted) return;
      if (result != null) {
        setState(() {
          _event = result;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Event not found';
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Event')),
        body: Center(child: Text('Failed to load: $_error')),
      );
    }
    return LargeEventScreen(event: _event!);
  }
}
