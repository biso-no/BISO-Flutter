import '../../widgets/home/discovery_sections.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/logging/app_logger.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../presentation/widgets/biso/biso.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../../providers/notification/notification_provider.dart';
import '../../../providers/ui/locale_provider.dart';
import '../../../presentation/widgets/dynamic_hero_carousel.dart';

import '../../../providers/large_event/large_event_provider.dart';
import '../../../data/services/event_service.dart';
import '../../../data/services/job_service.dart';
import '../../../data/services/webshop_service.dart';
import '../../../data/models/event_model.dart';
import '../../../data/models/job_model.dart';
import '../../../data/models/webshop_product_model.dart';
import '../../../data/models/news_model.dart';
import '../../../providers/news/news_provider.dart';
import '../../widgets/campus/campus_switcher_sheet.dart';
import '../../widgets/home/home_benefits_section.dart';
import '../../widgets/home/news_carousel.dart';
import '../auth/login_screen.dart';

// === PREMIUM HOME PAGE ===

class PremiumHomePage extends ConsumerWidget {
  final Function(int) navigateToTab;

  const PremiumHomePage({super.key, required this.navigateToTab});

  // Data providers
  static final _eventServiceProvider = Provider<EventService>(
    (ref) => EventService(),
  );
  static final _webshopServiceProvider = Provider<WebshopService>(
    (ref) => WebshopService(),
  );
  static final _jobServiceProvider = Provider<JobService>(
    (ref) => JobService(),
  );

  static final _latestEventsProvider =
      FutureProvider.family<List<EventModel>, String>((ref, campusId) async {
        final service = ref.watch(_eventServiceProvider);
        final locale = ref.watch(localeProvider).languageCode;
        final stopwatch = Stopwatch()..start();
        AppLogger.info(
          '[HOME] Loading latest events',
          extra: {
            'section': 'events',
            'campus_id': campusId,
            'source': 'appwrite',
            'limit': 6,
          },
        );

        try {
          final events = await service.listEvents(
            campusId: campusId,
            locale: locale,
            limit: 6,
            includePast: false,
          );

          stopwatch.stop();
          AppLogger.info(
            '[HOME] Latest events loaded',
            extra: {
              'section': 'events',
              'campus_id': campusId,
              'source': 'appwrite',
              'count': events.length,
              'duration_ms': stopwatch.elapsedMilliseconds,
              'sample_ids': events.take(3).map((event) => event.id).toList(),
            },
          );
          return events;
        } catch (error, stackTrace) {
          stopwatch.stop();
          AppLogger.error(
            '[HOME] Latest events failed',
            error: error,
            stackTrace: stackTrace,
            extra: {
              'section': 'events',
              'campus_id': campusId,
              'source': 'appwrite',
              'duration_ms': stopwatch.elapsedMilliseconds,
            },
          );
          rethrow;
        }
      });

  static final _latestWebshopProductsProvider =
      FutureProvider.family<List<WebshopProduct>, String>((
        ref,
        campusId,
      ) async {
        final service = ref.watch(_webshopServiceProvider);
        final locale = ref.watch(localeProvider).languageCode;
        final stopwatch = Stopwatch()..start();
        AppLogger.info(
          '[HOME] Loading latest webshop products',
          extra: {'section': 'webshop', 'campus_id': campusId, 'limit': 6},
        );
        try {
          final products = await service.listProducts(
            campusId: campusId,
            locale: locale,
            limit: 6,
          );
          stopwatch.stop();
          AppLogger.info(
            '[HOME] Latest webshop products loaded',
            extra: {
              'section': 'webshop',
              'campus_id': campusId,
              'count': products.length,
              'duration_ms': stopwatch.elapsedMilliseconds,
              'sample_ids': products
                  .take(3)
                  .map((product) => product.id)
                  .toList(),
            },
          );
          return products;
        } catch (error, stackTrace) {
          stopwatch.stop();
          AppLogger.error(
            '[HOME] Latest webshop products failed',
            error: error,
            stackTrace: stackTrace,
            extra: {
              'section': 'webshop',
              'campus_id': campusId,
              'duration_ms': stopwatch.elapsedMilliseconds,
            },
          );
          rethrow;
        }
      });

  static final _latestJobsProvider =
      FutureProvider.family<List<JobModel>, String>((ref, campusId) async {
        final service = ref.watch(_jobServiceProvider);
        final locale = ref.watch(localeProvider).languageCode;
        final stopwatch = Stopwatch()..start();
        AppLogger.info(
          '[HOME] Loading latest jobs',
          extra: {
            'section': 'jobs',
            'campus_id': campusId,
            'limit': 6,
            'include_expired': false,
          },
        );
        try {
          final jobs = await service.listJobs(
            campusId: campusId,
            locale: locale,
            limit: 6,
            includeExpired: false,
          );
          stopwatch.stop();
          AppLogger.info(
            '[HOME] Latest jobs loaded',
            extra: {
              'section': 'jobs',
              'campus_id': campusId,
              'count': jobs.length,
              'duration_ms': stopwatch.elapsedMilliseconds,
              'sample_ids': jobs.take(3).map((job) => job.id).toList(),
            },
          );
          return jobs;
        } catch (error, stackTrace) {
          stopwatch.stop();
          AppLogger.error(
            '[HOME] Latest jobs failed',
            error: error,
            stackTrace: stackTrace,
            extra: {
              'section': 'jobs',
              'campus_id': campusId,
              'duration_ms': stopwatch.elapsedMilliseconds,
            },
          );
          rethrow;
        }
      });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campus = ref.watch(filterCampusProvider);
    final isCampusReady =
        ref.watch(campusInitializedProvider) && campus.id.isNotEmpty;
    ref.watch(authStateProvider);
    final l10n = AppLocalizations.of(context)!;

    final showcaseItems = ref.watch(heroShowcaseItemsProvider);
    final campusId = campus.id;

    if (!isCampusReady) {
      AppLogger.debug(
        '[HOME] Waiting for campus before loading content sections',
        extra: {
          'campus_id': campus.id,
          'campus_name': campus.name,
          'is_initialized': ref.watch(campusInitializedProvider),
        },
      );
    }

    final eventsAsync = isCampusReady
        ? ref.watch(_latestEventsProvider(campusId))
        : const AsyncLoading<List<EventModel>>();
    final newsAsync = isCampusReady
        ? ref.watch(latestNewsProvider(campusId))
        : const AsyncLoading<List<NewsModel>>();
    final webshopProductsAsync = isCampusReady
        ? ref.watch(_latestWebshopProductsProvider(campus.id))
        : const AsyncLoading<List<WebshopProduct>>();
    final jobsAsync = isCampusReady
        ? ref.watch(_latestJobsProvider(campusId))
        : const AsyncLoading<List<JobModel>>();

    return BisoPage(
      overImage: true,
      title: campus.name,
      largeTitle: false,
      actions: [
        BisoHeaderAction(
          icon: CupertinoIcons.bell,
          tooltip: l10n.notificationsMessage,
          badge: ref.watch(unreadCountProvider),
          onPressed: () => context.push('/notifications'),
        ),
      ],
      slivers: [
        // Dynamic Hero Carousel Section
        SliverToBoxAdapter(
          child: DynamicHeroCarousel(
            campus: campus,
            showcaseItems: showcaseItems,
            onCampusTap: () => _showCampusSwitcher(context, ref),
          ),
        ),

        // Latest Events Section
        _buildPremiumContentSection(
          title: l10n.happeningAtMessage(campus.name),
          onViewAll: () => context.go('/explore/events'),
          asyncData: eventsAsync,
          campusId: campusId,
          contentBuilder: (items) =>
              BisoEventCarousel(events: items.cast<EventModel>()),
          ref: ref,
          providerFamily: _latestEventsProvider,
          context: context,
        ),

        // Member benefits ("Fordeler for deg")
        if (isCampusReady) HomeBenefitsSection(campusId: campusId),

        // Latest News Section
        _buildPremiumContentSection<NewsModel>(
          title: l10n.latestNewsTitle,
          onViewAll: () => context.go('/explore/news'),
          asyncData: newsAsync,
          campusId: campusId,
          contentBuilder: (items) => BisoNewsCarousel(news: items),
          ref: ref,
          providerFamily: latestNewsProvider,
          context: context,
        ),

        // Webshop Section
        _buildPremiumContentSection(
          title: l10n.bisoWebshopMessage,
          onViewAll: () => context.go('/explore/products'),
          asyncData: webshopProductsAsync,
          campusId: campusId,
          contentBuilder: (items) =>
              BisoWebshopCarousel(products: items.cast<WebshopProduct>()),
          ref: ref,
          providerFamily: _latestWebshopProductsProvider,
          context: context,
        ),

        // Volunteer Opportunities Section
        _buildPremiumContentSection(
          title: l10n.openPositionsMessage,
          onViewAll: () => context.go('/explore/volunteer'),
          asyncData: jobsAsync,
          campusId: campusId,
          contentBuilder: (items) => BisoJobList(jobs: items.cast<JobModel>()),
          ref: ref,
          providerFamily: _latestJobsProvider,
          context: context,
        ),
      ],
    );
  }

  SliverToBoxAdapter _buildPremiumContentSection<T>({
    required String title,
    required VoidCallback onViewAll,
    required AsyncValue<List<T>> asyncData,
    required String campusId,
    required Widget Function(List<T>) contentBuilder,
    required WidgetRef ref,
    required dynamic providerFamily,
    required BuildContext context,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 32, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: text.headlineSmall?.copyWith(color: palette.ink),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onViewAll,
                  child: Text(l10n.viewAllMessage),
                ),
              ],
            ),
          ),
          asyncData.when(
            data: (items) => items.isEmpty
                ? BisoEmptyState(
                    icon: CupertinoIcons.tray,
                    title: l10n.nothingHereYetCheckBackSoonMessage,
                  )
                : contentBuilder(items),
            loading: () => const BisoSkeleton.card(),
            error: (_, _) => BisoErrorState(
              message: l10n.failedToLoadContentMessage,
              onRetry: () => ref.invalidate(providerFamily(campusId)),
            ),
          ),
        ],
      ),
    );
  }

  void _showCampusSwitcher(BuildContext context, WidgetRef ref) {
    showCampusSwitcher(
      context,
      selectedCampusId: ref.read(filterCampusProvider).id,
      onSelected: (campus) {
        ref.read(filterCampusStateProvider.notifier).selectFilterCampus(campus);
      },
    );
  }
}

// Old _PremiumHeroSection and _CampusButton classes removed
// They have been replaced by the DynamicHeroCarousel widget

// === AUTH REQUIRED PAGE ===

class PremiumAuthRequiredPage extends ConsumerWidget {
  final String title;
  final String description;
  final IconData icon;
  final Function(int)? navigateToTab;

  const PremiumAuthRequiredPage({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.navigateToTab,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return BisoPage(
      title: title,
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: BisoEmptyState(
            icon: icon,
            title: title,
            message: description,
            action: FilledButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              },
              child: Text(l10n.signInMessage),
            ),
          ),
        ),
      ],
    );
  }
}
