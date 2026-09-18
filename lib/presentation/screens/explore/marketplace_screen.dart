import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../data/models/product_model.dart';
import '../../../data/services/product_service.dart';
import '../../../data/models/webshop_product_model.dart';
import '../../../data/services/webshop_service.dart';
import '../../../data/services/feature_flag_service.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/ui/locale_provider.dart';
import '../../../providers/shop/cart_provider.dart';
import '../../widgets/biso/biso.dart';

final _productServiceProvider = Provider<ProductService>(
  (ref) => ProductService(),
);

final _webshopServiceProvider = Provider<WebshopService>(
  (ref) => WebshopService(),
);

final _featureFlagServiceProvider = Provider<FeatureFlagService>(
  (ref) => FeatureFlagService(),
);

final marketplaceFeatureEnabledProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(_featureFlagServiceProvider);
  return service.isEnabled('marketplace');
});

final productsProvider = FutureProvider.autoDispose
    .family<List<ProductModel>, _ProductQuery>((ref, query) async {
      final service = ref.watch(_productServiceProvider);
      final stopwatch = Stopwatch()..start();
      AppLogger.info(
        '[MARKETPLACE_SCREEN] Loading marketplace products',
        extra: query.toLogMap(),
      );

      try {
        final products = query.showFavorites && query.userId != null
            ? await service.getUserFavoriteProducts(
                userId: query.userId!,
                campusId: query.campusId,
                category: query.category,
                limit: 50,
              )
            : await service.listProducts(
                campusId: query.campusId,
                category: query.category,
                status: query.status,
                search: query.search,
                limit: 50,
              );
        stopwatch.stop();
        AppLogger.info(
          '[MARKETPLACE_SCREEN] Marketplace products loaded',
          extra: {
            ...query.toLogMap(),
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
          '[MARKETPLACE_SCREEN] Marketplace products failed',
          error: error,
          stackTrace: stackTrace,
          extra: {
            ...query.toLogMap(),
            'duration_ms': stopwatch.elapsedMilliseconds,
          },
        );
        rethrow;
      }
    });

final webshopProductsProvider = FutureProvider.autoDispose
    .family<List<WebshopProduct>, _WebshopQuery>((ref, query) async {
      final service = ref.watch(_webshopServiceProvider);
      final locale = ref.watch(localeProvider).languageCode;
      final stopwatch = Stopwatch()..start();
      AppLogger.info(
        '[MARKETPLACE_SCREEN] Loading webshop products',
        extra: query.toLogMap(),
      );
      try {
        final products = await service.listProducts(
          campusId: query.campusId,
          locale: locale,
          limit: 20,
          search: query.search,
        );
        stopwatch.stop();
        AppLogger.info(
          '[MARKETPLACE_SCREEN] Webshop products loaded',
          extra: {
            ...query.toLogMap(),
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
          '[MARKETPLACE_SCREEN] Webshop products failed',
          error: error,
          stackTrace: stackTrace,
          extra: {
            ...query.toLogMap(),
            'duration_ms': stopwatch.elapsedMilliseconds,
          },
        );
        rethrow;
      }
    });

class MarketplaceScreen extends ConsumerStatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  ConsumerState<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends ConsumerState<MarketplaceScreen> {
  _ShopMode _mode = _ShopMode.webshop;
  String _selectedCategory = 'all';
  String? _search;
  bool _showFavorites = false;
  Timer? _debounceTimer;

  // Paging state (marketplace mode uses Appwrite with offset; webshop uses page)
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 1;
  static const int _pageSize = 20;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  final List<WebshopProduct> _webshopAccumulated = [];
  // Which query the accumulated webshop pages belong to. Mirrors
  // `_loadedForCampusId` in events_screen/jobs_screen.
  String? _webshopLoadedForCampusId;
  String? _webshopLoadedForLocale;
  String? _lastProductsUiLogKey;

  final List<String> _categories = [
    'all',
    'books',
    'electronics',
    'furniture',
    'clothes',
    'sports',
    'other',
  ];

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _search = null;
        _resetWebshopPaging();
      });
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      final nextSearch = value.trim().isEmpty ? null : value.trim();
      AppLogger.info(
        '[MARKETPLACE_SCREEN] Search changed',
        extra: {
          'previous_search': _search,
          'next_search': nextSearch,
          'mode': _mode.name,
        },
      );
      setState(() {
        _search = nextSearch;
        // Reset webshop paging when search changes
        _resetWebshopPaging();
      });
    });
  }

  void _resetWebshopPaging() {
    AppLogger.debug(
      '[MARKETPLACE_SCREEN] Resetting webshop paging',
      extra: {
        'current_page': _currentPage,
        'accumulated_count': _webshopAccumulated.length,
      },
    );
    _currentPage = 1;
    _hasMore = true;
    _isLoadingMore = false;
    _webshopAccumulated.clear();
  }

  void _onScroll() async {
    if (_mode != _ShopMode.webshop) return;
    if (_isLoadingMore || !_hasMore) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      await _loadMoreWebshop();
    }
  }

  Future<void> _loadMoreWebshop() async {
    setState(() => _isLoadingMore = true);
    _currentPage += 1;
    final stopwatch = Stopwatch()..start();
    // Captured before the await so the request and its later staleness
    // check agree on which query this fetch was for, even though `_search`
    // is a mutable field that `_onSearchChanged` can reassign while this is
    // in flight.
    final campus = ref.read(filterCampusProvider);
    final locale = ref.read(localeProvider).languageCode;
    final search = _search;
    try {
      final service = ref.read(_webshopServiceProvider);
      final offset = (_currentPage - 1) * _pageSize;
      AppLogger.info(
        '[MARKETPLACE_SCREEN] Loading more webshop products',
        extra: {
          'campus_name': campus.name,
          'page': _currentPage,
          'offset': offset,
          'page_size': _pageSize,
          'current_count': _webshopAccumulated.length,
        },
      );
      final next = await service.listProducts(
        campusId: campus.id,
        locale: locale,
        limit: _pageSize,
        offset: offset,
        search: search,
      );
      stopwatch.stop();

      // The campus, locale, or search may have changed while this request
      // was in flight. Unlike events/jobs, the webshop provider itself
      // ref.watches locale (so a locale change already refetches page 1
      // under a new family key) — but this paging method still reads
      // campus/locale via ref.read and search via the `_search` field, so a
      // page fetched for the old campus/locale/search must never be
      // appended to the accumulator for the new one.
      //
      // Check `mounted` before touching `ref` at all: after dispose,
      // ConsumerStatefulElement.read throws StateError (not just a debug
      // assert), so reading providers here first would crash instead of
      // dropping silently.
      if (!mounted) return;
      final currentCampus = ref.read(filterCampusProvider);
      final currentLocale = ref.read(localeProvider).languageCode;
      if (currentCampus.id != campus.id ||
          currentLocale != locale ||
          _search != search) {
        AppLogger.info(
          '[MARKETPLACE_SCREEN] Dropping stale webshop page '
          '(campus/locale/search changed)',
          extra: {
            'requested_campus_id': campus.id,
            'current_campus_id': currentCampus.id,
            'requested_locale': locale,
            'current_locale': currentLocale,
            'requested_search': search,
            'current_search': _search,
            'page': _currentPage,
          },
        );
        // Release the paging latch before dropping this page: a
        // load-more that is discarded must not leave `_isLoadingMore`
        // latched, or the trailing spinner outlives the request that
        // raised it and _onScroll refuses to page again for the life of
        // the screen. Every axis that can invalidate a page also calls
        // _resetWebshopPaging(), which clears the flag; this release is
        // the guarantee that does not depend on each of them remembering
        // to. Unlike events_screen/jobs_screen there is no `replace`
        // case — this method is only ever a load-more — so it is
        // unconditional.
        setState(() => _isLoadingMore = false);
        return;
      }

      setState(() {
        _webshopAccumulated.addAll(next);
        _isLoadingMore = false;
        _hasMore = next.length >= _pageSize;
      });
      AppLogger.info(
        '[MARKETPLACE_SCREEN] More webshop products loaded',
        extra: {
          'campus_name': campus.name,
          'page': _currentPage,
          'returned_count': next.length,
          'accumulated_count': _webshopAccumulated.length,
          'has_more': _hasMore,
          'duration_ms': stopwatch.elapsedMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      stopwatch.stop();
      AppLogger.error(
        '[MARKETPLACE_SCREEN] Loading more webshop products failed',
        error: error,
        stackTrace: stackTrace,
        extra: {
          'page': _currentPage,
          'page_size': _pageSize,
          'duration_ms': stopwatch.elapsedMilliseconds,
        },
      );
      if (!mounted) return;
      // A late failure belongs to whichever campus/locale/search this
      // fetch was for. If the user has since switched away, disabling
      // paging now would kill it for a campus/search that never failed.
      final currentCampus = ref.read(filterCampusProvider);
      final currentLocale = ref.read(localeProvider).languageCode;
      if (currentCampus.id != campus.id ||
          currentLocale != locale ||
          _search != search) {
        AppLogger.info(
          '[MARKETPLACE_SCREEN] Dropping stale webshop page failure '
          '(campus/locale/search changed)',
          extra: {
            'requested_campus_id': campus.id,
            'current_campus_id': currentCampus.id,
            'requested_locale': locale,
            'current_locale': currentLocale,
            'requested_search': search,
            'current_search': _search,
            'page': _currentPage,
          },
        );
        // Release the paging latch before dropping this page: a
        // load-more that is discarded must not leave `_isLoadingMore`
        // latched, or the trailing spinner outlives the request that
        // raised it and _onScroll refuses to page again for the life of
        // the screen. Every axis that can invalidate a page also calls
        // _resetWebshopPaging(), which clears the flag; this release is
        // the guarantee that does not depend on each of them remembering
        // to. Unlike events_screen/jobs_screen there is no `replace`
        // case — this method is only ever a load-more — so it is
        // unconditional.
        setState(() => _isLoadingMore = false);
        return;
      }
      setState(() {
        _isLoadingMore = false;
        _hasMore = false;
      });
    }
  }

  /// Folds the provider's page 1 into the accumulated webshop list.
  ///
  /// The accumulator belongs to one campus/locale pair. When either changes
  /// the provider family refetches, and the accumulated pages are no longer
  /// the answer to the current query: keeping them would leave the previous
  /// campus's products on screen and make the next [_loadMoreWebshop] request
  /// the new campus at the old offset, skipping items. So the paging state is
  /// reset first, exactly as `_ensureInitialLoad` does in
  /// events_screen/jobs_screen. A search change is deliberately not part
  /// of that check: it resets the paging state at each of its sources —
  /// [_onSearchChanged] when the field is typed in, and the field's clear
  /// button for the X — so it always arrives in the empty-accumulator
  /// branch below.
  List<WebshopProduct> _computeWebshopList(
    List<WebshopProduct> firstPage, {
    required String campusId,
    required String locale,
  }) {
    if (_webshopLoadedForCampusId != campusId ||
        _webshopLoadedForLocale != locale) {
      AppLogger.info(
        '[MARKETPLACE_SCREEN] Webshop query changed; restarting paging',
        extra: {
          'previous_campus_id': _webshopLoadedForCampusId,
          'campus_id': campusId,
          'previous_locale': _webshopLoadedForLocale,
          'locale': locale,
          'discarded_count': _webshopAccumulated.length,
        },
      );
      _webshopLoadedForCampusId = campusId;
      _webshopLoadedForLocale = locale;
      _resetWebshopPaging();
    }
    if (_webshopAccumulated.isEmpty) {
      // initialize with first page
      _webshopAccumulated.addAll(firstPage);
    }
    return _webshopAccumulated;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final campus = ref.watch(filterCampusProvider);
    // The webshop provider resolves translations for this locale, so it is
    // part of the identity of the accumulated pages.
    final locale = ref.watch(localeProvider).languageCode;
    final isCampusReady =
        ref.watch(campusInitializedProvider) && campus.id.isNotEmpty;
    final auth = ref.watch(authStateProvider);

    final flagAsync = ref.watch(marketplaceFeatureEnabledProvider);

    final backButton = BisoBackButton(
      onPressed: () =>
          NavigationUtils.safeGoBack(context, fallbackRoute: '/home'),
    );

    // Show loading state before deciding mode
    if (flagAsync.isLoading) {
      AppLogger.debug(
        '[MARKETPLACE_SCREEN] Waiting for marketplace feature flag',
      );
      return BisoPage(
        title: l10n.webshopMessage,
        largeTitle: false,
        leading: backButton,
        slivers: const [SliverToBoxAdapter(child: BisoSkeleton.grid())],
      );
    }

    final bool marketplaceEnabled = flagAsync.hasError
        ? false
        : (flagAsync.value ?? false);
    if (flagAsync.hasError) {
      AppLogger.warning(
        '[MARKETPLACE_SCREEN] Marketplace feature flag failed; defaulting to webshop',
        error: flagAsync.error,
        stackTrace: flagAsync.stackTrace,
      );
    }
    final effectiveMode = marketplaceEnabled ? _mode : _ShopMode.webshop;
    final title = effectiveMode == _ShopMode.marketplace
        ? l10n.marketplaceMessage
        : l10n.webshopMessage;

    if (!isCampusReady) {
      AppLogger.debug(
        '[MARKETPLACE_SCREEN] Waiting for campus before loading products',
        extra: {
          'campus_id': campus.id,
          'campus_name': campus.name,
          'is_initialized': ref.watch(campusInitializedProvider),
        },
      );
      return BisoPage(
        title: title,
        largeTitle: false,
        leading: backButton,
        slivers: const [SliverToBoxAdapter(child: BisoSkeleton.grid())],
      );
    }

    final query = _ProductQuery(
      campusId: campus.id,
      category: _selectedCategory,
      status: 'available',
      search: _search,
      showFavorites: _showFavorites,
      userId: auth.isAuthenticated ? auth.user?.id : null,
    );
    final productsAsync = effectiveMode == _ShopMode.marketplace
        ? ref.watch(productsProvider(query))
        : const AsyncData<List<ProductModel>>([]);
    final webshopQuery = _WebshopQuery(
      campusId: campus.id,
      campusName: campus.name,
      departmentId: null,
      search: _search,
    );
    final webshopAsync = effectiveMode == _ShopMode.webshop
        ? ref.watch(webshopProductsProvider(webshopQuery))
        : const AsyncData<List<WebshopProduct>>([]);

    // attach scroll listener for webshop infinite scroll
    _scrollController.removeListener(_onScroll);
    _scrollController.addListener(_onScroll);

    return BisoPage(
      title: title,
      leading: backButton,
      controller: _scrollController,
      search: (effectiveMode == _ShopMode.marketplace && _showFavorites)
          ? null
          : BisoHeaderSearch(
              hintText: effectiveMode == _ShopMode.marketplace
                  ? l10n.searchMarketplaceMessage
                  : l10n.searchWebshopMessage,
              initialQuery: _search ?? '',
              debounce: Duration.zero,
              onChanged: _onSearchChanged,
            ),
      actions: [
        if (auth.isAuthenticated && effectiveMode == _ShopMode.marketplace)
          BisoHeaderAction(
            icon: _showFavorites ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
            tooltip: _showFavorites ? 'Show all products' : 'Show favorites only',
            onPressed: () {
              setState(() {
                _showFavorites = !_showFavorites;
                if (_showFavorites) {
                  // Clear search when switching to favorites
                  _debounceTimer?.cancel();
                  _search = null;
                }
              });
            },
          ),
        // The webshop is the only mode that sells through the BISO cart;
        // marketplace listings are student-to-student and settled between
        // the two of them. `cartItemCountProvider` is only watched when
        // this action actually renders.
        if (effectiveMode == _ShopMode.webshop) _buildCartAction(),
        if (effectiveMode == _ShopMode.marketplace)
          BisoHeaderAction(
            icon: CupertinoIcons.plus,
            tooltip: 'Sell Item',
            onPressed: () => context.go('/explore/products/new'),
          ),
      ],
      slivers: [
        // Segmented toggle for modes (shown only when feature flag enabled)
        if (marketplaceEnabled)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Marketplace'),
                      selected: effectiveMode == _ShopMode.marketplace,
                      onSelected: (_) => setState(() {
                        AppLogger.info(
                          '[MARKETPLACE_SCREEN] Mode changed',
                          extra: {
                            'previous_mode': effectiveMode.name,
                            'next_mode': _ShopMode.marketplace.name,
                          },
                        );
                        _mode = _ShopMode.marketplace;
                        _search = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Webshop'),
                      selected: effectiveMode == _ShopMode.webshop,
                      onSelected: (_) => setState(() {
                        AppLogger.info(
                          '[MARKETPLACE_SCREEN] Mode changed',
                          extra: {
                            'previous_mode': effectiveMode.name,
                            'next_mode': _ShopMode.webshop.name,
                          },
                        );
                        _mode = _ShopMode.webshop;
                        _showFavorites = false;
                        _selectedCategory = 'all';
                        _resetWebshopPaging();
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Category filter (marketplace only)
        if (effectiveMode == _ShopMode.marketplace)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                children: [
                  for (final cat in _categories) ...[
                    ChoiceChip(
                      label: Text(_getCategoryDisplayName(cat)),
                      selected: cat == _selectedCategory,
                      onSelected: (_) =>
                          setState(() => _selectedCategory = cat),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
        ...(effectiveMode == _ShopMode.marketplace ? productsAsync : webshopAsync)
            .when(
              data: (products) {
                final visibleProducts = effectiveMode == _ShopMode.webshop
                    ? _computeWebshopList(
                        products as List<WebshopProduct>,
                        campusId: campus.id,
                        locale: locale,
                      )
                    : products;
                _logProductsUiState(
                  mode: effectiveMode,
                  campusId: campus.id,
                  campusName: campus.name,
                  visibleCount: visibleProducts.length,
                );

                if (visibleProducts.isEmpty) {
                  return [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: BisoEmptyState(
                        icon: CupertinoIcons.bag,
                        accent: BisoAccent.gold,
                        title: _showFavorites
                            ? 'No favorites yet'
                            : 'No items found',
                        message: _showFavorites
                            ? 'Heart items you like to see them here!'
                            : 'Try changing your filter or check back later',
                      ),
                    ),
                  ];
                }

                return [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        mainAxisExtent: _gridMainAxisExtent(
                          context,
                          effectiveMode,
                        ),
                      ),
                      itemCount: (effectiveMode == _ShopMode.webshop)
                          ? _computeWebshopList(
                                  products as List<WebshopProduct>,
                                  campusId: campus.id,
                                  locale: locale,
                                ).length +
                                (_isLoadingMore ? 1 : 0)
                          : products.length,
                      itemBuilder: (context, index) {
                        if (effectiveMode == _ShopMode.marketplace) {
                          return _PremiumProductCard(
                            product: products[index] as ProductModel,
                          );
                        } else {
                          final list = _computeWebshopList(
                            products as List<WebshopProduct>,
                            campusId: campus.id,
                            locale: locale,
                          );
                          if (index >= list.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          return _WebshopProductCard(product: list[index]);
                        }
                      },
                    ),
                  ),
                ];
              },
              loading: () =>
                  const [SliverToBoxAdapter(child: BisoSkeleton.grid())],
              error: (e, st) {
                AppLogger.error(
                  '[MARKETPLACE_SCREEN] Products section rendered error',
                  error: e,
                  stackTrace: st,
                  extra: {
                    'mode': effectiveMode.name,
                    'campus_id': campus.id,
                    'campus_name': campus.name,
                    'search': _search,
                    'selected_category': _selectedCategory,
                    'show_favorites': _showFavorites,
                  },
                );
                return [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: BisoErrorState(
                      onRetry: () {
                        if (effectiveMode == _ShopMode.marketplace) {
                          ref.invalidate(productsProvider(query));
                        } else {
                          ref.invalidate(
                            webshopProductsProvider(webshopQuery),
                          );
                        }
                      },
                    ),
                  ),
                ];
              },
            ),
      ],
    );
  }

  void _logProductsUiState({
    required _ShopMode mode,
    required String campusId,
    required String campusName,
    required int visibleCount,
  }) {
    final key = [
      mode.name,
      campusId,
      campusName,
      _selectedCategory,
      _search,
      _showFavorites,
      visibleCount,
      _hasMore,
      _isLoadingMore,
    ].join('|');
    if (_lastProductsUiLogKey == key) return;
    _lastProductsUiLogKey = key;

    final extra = {
      'mode': mode.name,
      'campus_id': campusId,
      'campus_name': campusName,
      'selected_category': _selectedCategory,
      'search': _search,
      'show_favorites': _showFavorites,
      'visible_count': visibleCount,
      'has_more': _hasMore,
      'is_loading_more': _isLoadingMore,
    };

    if (visibleCount == 0) {
      AppLogger.warning(
        '[MARKETPLACE_SCREEN] No visible products after filters',
        extra: extra,
      );
    } else {
      AppLogger.info(
        '[MARKETPLACE_SCREEN] Rendering visible products',
        extra: extra,
      );
    }
  }

  /// Reads `cartItemCountProvider` only when the cart header action is
  /// about to render (webshop mode), rather than unconditionally on every
  /// build.
  BisoHeaderAction _buildCartAction() {
    final count = ref.watch(cartItemCountProvider);
    return BisoHeaderAction(
      icon: CupertinoIcons.bag,
      tooltip: count == 0
          ? 'Your cart'
          : 'Your cart, $count ${count == 1 ? 'item' : 'items'}',
      badge: count,
      onPressed: () => context.push('/explore/products/cart'),
    );
  }

  String _getCategoryDisplayName(String category) {
    switch (category) {
      case 'all':
        return 'All';
      case 'books':
        return 'Books';
      case 'electronics':
        return 'Electronics';
      case 'furniture':
        return 'Furniture';
      case 'clothes':
        return 'Clothes';
      case 'sports':
        return 'Sports';
      case 'other':
        return 'Other';
      default:
        return category;
    }
  }
}

enum _ShopMode { marketplace, webshop }

/// Scaled height of one line of [style]. Same approximation as
/// `_scaledLineHeight` in `lib/presentation/widgets/home/discovery_sections.dart`
/// (fontSize * height, scaled by the device's text scaler), reproduced here
/// because that one is private to its own library.
double _scaledLineHeight(BuildContext context, TextStyle? style) =>
    MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 14) *
    (style?.height ?? 1.4);

/// The product grid's `mainAxisExtent`, sized to the card's actual content
/// at the device's text scale instead of a fixed `childAspectRatio`. No
/// single ratio fits both text scales and both card shapes: a marketplace
/// card carries one more text row (seller/condition) than a webshop card,
/// and 1.6x text overflows a ratio tuned for 1.0x while 1.0x leaves a blank
/// band under a ratio tuned for 1.6x.
///
/// The extent is the image (the grid column is square, per the cards'
/// `AspectRatio(aspectRatio: 1)`) plus the card's own padding plus every
/// text line the card renders, each measured with the exact `TextStyle` and
/// `maxLines` the card uses (mirrors `_WebshopProductCard` and
/// `_PremiumProductCard` below).
double _gridMainAxisExtent(BuildContext context, _ShopMode mode) {
  final theme = Theme.of(context);
  final width = MediaQuery.sizeOf(context).width;
  // The SliverPadding around the grid (horizontal: 16) and the grid's own
  // crossAxisSpacing (14) between the two columns.
  final columnWidth = (width - 16 * 2 - 14) / 2;
  final imageHeight = columnWidth;

  // EdgeInsets.fromLTRB(12, 8, 12, 8) in both cards' info Padding: only the
  // vertical 8 + 8 affects the column height.
  const cardPadding = 8.0 + 8.0;
  const titlePriceGap = 4.0;
  final titleHeight =
      _scaledLineHeight(context, theme.textTheme.titleSmall) * 2; // maxLines: 2
  final priceHeight = _scaledLineHeight(context, theme.textTheme.titleMedium);

  var extent = imageHeight + cardPadding + titleHeight + titlePriceGap + priceHeight;

  if (mode == _ShopMode.marketplace) {
    // `_PremiumProductCard` alone adds a seller-name / condition-badge row
    // below the price. The badge's own vertical padding (2 + 2, not
    // text-scaled) can outgrow the (text-scaled) seller line at small text
    // scale, so the row takes whichever of the two is taller.
    const priceRowGap = 4.0;
    const badgePadding = 2.0 + 2.0;
    final sellerRowHeight = _scaledLineHeight(context, theme.textTheme.bodySmall);
    final badgeRowHeight =
        badgePadding + _scaledLineHeight(context, theme.textTheme.labelSmall);
    extent +=
        priceRowGap +
        (sellerRowHeight > badgeRowHeight ? sellerRowHeight : badgeRowHeight);
  }

  return extent;
}

/// Nearest CupertinoIcons for a marketplace category. Not in the R7 table:
/// electronics -> device_laptop, furniture -> house_fill, clothes -> tag,
/// sports -> sportscourt, other/unknown -> bag.
IconData _categoryIcon(String category) {
  switch (category) {
    case 'books':
      return CupertinoIcons.book;
    case 'electronics':
      return CupertinoIcons.device_laptop;
    case 'furniture':
      return CupertinoIcons.house_fill;
    case 'clothes':
      return CupertinoIcons.tag;
    case 'sports':
      return CupertinoIcons.sportscourt;
    default:
      return CupertinoIcons.bag;
  }
}

/// One color per condition, best to worst. `new`/`like_new` map onto the two
/// positive meanings the palette has (success/link); `good` has no semantic
/// meaning of its own so it stays neutral; `fair`/`poor` map onto warning and
/// error.
Color _conditionColor(BisoPalette palette, String condition) {
  switch (condition) {
    case 'new':
      return palette.success;
    case 'like_new':
      return palette.link;
    case 'fair':
      return palette.warning;
    case 'poor':
      return palette.error;
    default:
      return palette.muted;
  }
}

class _WebshopProductCard extends StatelessWidget {
  final WebshopProduct product;

  const _WebshopProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    final priceText = 'NOK ${product.regularPrice.toStringAsFixed(0)}';

    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          context.pushNamed(
            'webshop-product-detail',
            pathParameters: {'productId': product.id},
            extra: product,
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  product.images.isNotEmpty
                      ? Image.network(
                          product.images.first,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _ProductImagePlaceholder(
                            palette: palette,
                            icon: CupertinoIcons.bag,
                          ),
                        )
                      : _ProductImagePlaceholder(
                          palette: palette,
                          icon: CupertinoIcons.bag,
                        ),
                  // On the image, not under the price: the card's height is
                  // measured from its text lines.
                  if (product.memberOnly)
                    const PositionedDirectional(
                      top: 8,
                      start: 8,
                      end: 8,
                      child: Align(
                        alignment: AlignmentDirectional.topStart,
                        child: BisoMembersBadge(),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      product.title ?? '',
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      priceText,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: palette.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductImagePlaceholder extends StatelessWidget {
  const _ProductImagePlaceholder({required this.palette, required this.icon});

  final BisoPalette palette;
  final IconData icon;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: palette.surfaceRaised,
    child: Center(
      child: BisoIconTile(icon: icon, accent: BisoAccent.gold, size: 48),
    ),
  );
}

class _WebshopQuery {
  final String campusId;
  final String campusName;
  final String? departmentId;
  final String? search;

  const _WebshopQuery({
    required this.campusId,
    required this.campusName,
    this.departmentId,
    this.search,
  });

  Map<String, dynamic> toLogMap() => {
    'campus_id': campusId,
    'campus_name': campusName,
    'department_id': departmentId,
    'search': search,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _WebshopQuery &&
        other.campusId == campusId &&
        other.campusName == campusName &&
        other.departmentId == departmentId &&
        other.search == search;
  }

  @override
  int get hashCode => Object.hash(campusId, campusName, departmentId, search);
}

class _PremiumProductCard extends ConsumerStatefulWidget {
  final ProductModel product;

  const _PremiumProductCard({required this.product});

  @override
  ConsumerState<_PremiumProductCard> createState() =>
      _PremiumProductCardState();
}

class _PremiumProductCardState extends ConsumerState<_PremiumProductCard> {
  bool _isFavorited = false;
  bool _favoriteLoading = false;

  @override
  void initState() {
    super.initState();
    _checkFavoriteStatus();
  }

  Future<void> _checkFavoriteStatus() async {
    final auth = ref.read(authStateProvider);
    if (auth.isAuthenticated && auth.user != null) {
      try {
        final service = ProductService();
        final isFavorited = await service.isFavorited(
          userId: auth.user!.id,
          productId: widget.product.id,
        );
        if (mounted) {
          setState(() {
            _isFavorited = isFavorited;
          });
        }
      } catch (e) {
        // Silently fail - favorite status is not critical
      }
    }
  }

  Future<void> _toggleFavorite() async {
    final auth = ref.read(authStateProvider);
    if (!auth.isAuthenticated || auth.user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to save favorites')),
        );
      }
      return;
    }

    if (_favoriteLoading) return;

    if (mounted) {
      setState(() => _favoriteLoading = true);
    }

    try {
      final service = ProductService();
      final newState = await service.toggleFavorite(
        userId: auth.user!.id,
        productId: widget.product.id,
      );

      if (mounted) {
        setState(() {
          _isFavorited = newState;
          _favoriteLoading = false;
        });

        // Show subtle feedback
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newState ? 'Added to favorites' : 'Removed from favorites',
            ),
            duration: const Duration(milliseconds: 800),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _favoriteLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update favorite: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    final auth = ref.watch(authStateProvider);

    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/explore/products/${widget.product.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with favorite overlay
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: widget.product.images.isNotEmpty
                        ? Image.network(
                            widget.product.images.first,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _ProductImagePlaceholder(
                              palette: palette,
                              icon: _categoryIcon(widget.product.category),
                            ),
                          )
                        : _ProductImagePlaceholder(
                            palette: palette,
                            icon: _categoryIcon(widget.product.category),
                          ),
                  ),
                  if (auth.isAuthenticated)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: _toggleFavorite,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: palette.surface,
                            shape: BoxShape.circle,
                          ),
                          child: _favoriteLoading
                              ? Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: palette.link,
                                  ),
                                )
                              : Icon(
                                  _isFavorited
                                      ? CupertinoIcons.heart_fill
                                      : CupertinoIcons.heart,
                                  color: _isFavorited
                                      ? palette.error
                                      : palette.link,
                                  size: 18,
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Info - flexible content area
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.product.name,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'NOK ${widget.product.price.toStringAsFixed(0)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: palette.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.product.sellerName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: palette.muted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _conditionColor(
                              palette,
                              widget.product.condition,
                            ).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            widget.product.displayCondition,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: _conditionColor(
                                palette,
                                widget.product.condition,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductQuery {
  final String campusId;
  final String? category;
  final String? status;
  final String? search;
  final bool showFavorites;
  final String? userId;

  const _ProductQuery({
    required this.campusId,
    this.category,
    this.status,
    this.search,
    this.showFavorites = false,
    this.userId,
  });

  Map<String, dynamic> toLogMap() => {
    'campus_id': campusId,
    'category': category,
    'status': status,
    'search': search,
    'show_favorites': showFavorites,
    'user_id': userId,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _ProductQuery &&
        other.campusId == campusId &&
        other.category == category &&
        other.status == status &&
        other.search == search &&
        other.showFavorites == showFavorites &&
        other.userId == userId;
  }

  @override
  int get hashCode =>
      Object.hash(campusId, category, status, search, showFavorites, userId);
}
