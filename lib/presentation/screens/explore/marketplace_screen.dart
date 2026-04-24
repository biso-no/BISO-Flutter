import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/logging/app_logger.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../data/models/product_model.dart';
import '../../../data/services/product_service.dart';
import '../../../data/models/webshop_product_model.dart';
import '../../../data/services/webshop_service.dart';
import '../../../data/services/feature_flag_service.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../../providers/auth/auth_provider.dart';

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
      final stopwatch = Stopwatch()..start();
      AppLogger.info(
        '[MARKETPLACE_SCREEN] Loading webshop products',
        extra: query.toLogMap(),
      );
      try {
        final products = await service.listWebshopProducts(
          campusId: query.campusId,
          campusName: query.campusName,
          departmentId: query.departmentId,
          limit: 20,
          page: 1,
        );
        final filtered = query.search == null || query.search!.isEmpty
            ? products
            : products
                  .where(
                    (p) => p.name.toLowerCase().contains(
                      query.search!.toLowerCase(),
                    ),
                  )
                  .toList(growable: false);
        stopwatch.stop();
        AppLogger.info(
          '[MARKETPLACE_SCREEN] Webshop products loaded',
          extra: {
            ...query.toLogMap(),
            'raw_count': products.length,
            'filtered_count': filtered.length,
            'duration_ms': stopwatch.elapsedMilliseconds,
            'sample_ids': filtered
                .take(3)
                .map((product) => product.id.toString())
                .toList(),
          },
        );
        return filtered;
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
  final TextEditingController _searchController = TextEditingController();

  // Paging state (marketplace mode uses Appwrite with offset; webshop uses page)
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 1;
  static const int _pageSize = 20;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  final List<WebshopProduct> _webshopAccumulated = [];
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
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
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
    try {
      final service = ref.read(_webshopServiceProvider);
      final campus = ref.read(filterCampusProvider);
      AppLogger.info(
        '[MARKETPLACE_SCREEN] Loading more webshop products',
        extra: {
          'campus_name': campus.name,
          'page': _currentPage,
          'page_size': _pageSize,
          'current_count': _webshopAccumulated.length,
        },
      );
      final next = await service.listWebshopProducts(
        campusId: campus.id,
        campusName: campus.name,
        departmentId: null,
        limit: _pageSize,
        page: _currentPage,
      );
      stopwatch.stop();
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
      setState(() {
        _isLoadingMore = false;
        _hasMore = false;
      });
    }
  }

  List<WebshopProduct> _computeWebshopList(List<WebshopProduct> firstPage) {
    if (_webshopAccumulated.isEmpty) {
      // initialize with first page
      _webshopAccumulated.addAll(firstPage);
    }
    return _webshopAccumulated;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final campus = ref.watch(filterCampusProvider);
    final isCampusReady =
        ref.watch(campusInitializedProvider) && campus.id.isNotEmpty;
    final auth = ref.watch(authStateProvider);

    final flagAsync = ref.watch(marketplaceFeatureEnabledProvider);

    // Show loading state before deciding mode
    if (flagAsync.isLoading) {
      AppLogger.debug(
        '[MARKETPLACE_SCREEN] Waiting for marketplace feature flag',
      );
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(l10n.webshopMessage),
          centerTitle: true,
          elevation: 0,
          backgroundColor: theme.appBarTheme.backgroundColor,
          leading: IconButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/home'),
            icon: const Icon(Icons.arrow_back, color: AppColors.charcoalBlack),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
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

    if (!isCampusReady) {
      AppLogger.debug(
        '[MARKETPLACE_SCREEN] Waiting for campus before loading products',
        extra: {
          'campus_id': campus.id,
          'campus_name': campus.name,
          'is_initialized': ref.watch(campusInitializedProvider),
        },
      );
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            effectiveMode == _ShopMode.marketplace
                ? l10n.marketplaceMessage
                : l10n.webshopMessage,
          ),
          centerTitle: true,
          elevation: 0,
          backgroundColor: theme.appBarTheme.backgroundColor,
          leading: IconButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/home'),
            icon: const Icon(Icons.arrow_back, color: AppColors.charcoalBlack),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          effectiveMode == _ShopMode.marketplace
              ? l10n.marketplaceMessage
              : l10n.webshopMessage,
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: theme.appBarTheme.backgroundColor,
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
          icon: const Icon(Icons.arrow_back, color: AppColors.charcoalBlack),
        ),
        actions: [
          if (auth.isAuthenticated && effectiveMode == _ShopMode.marketplace)
            IconButton(
              onPressed: () {
                setState(() {
                  _showFavorites = !_showFavorites;
                  if (_showFavorites) {
                    // Clear search when switching to favorites
                    _searchController.clear();
                    _search = null;
                  }
                });
              },
              icon: Icon(
                _showFavorites ? Icons.favorite : Icons.favorite_border,
                color: _showFavorites
                    ? AppColors.error
                    : AppColors.charcoalBlack,
              ),
              tooltip: _showFavorites
                  ? 'Show all products'
                  : 'Show favorites only',
            ),
        ],
      ),
      body: Column(
        children: [
          // Segmented toggle for modes (shown only when feature flag enabled)
          if (marketplaceEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    _ModeChip(
                      label: 'Marketplace',
                      selected: effectiveMode == _ShopMode.marketplace,
                      onTap: () => setState(() {
                        AppLogger.info(
                          '[MARKETPLACE_SCREEN] Mode changed',
                          extra: {
                            'previous_mode': effectiveMode.name,
                            'next_mode': _ShopMode.marketplace.name,
                          },
                        );
                        _mode = _ShopMode.marketplace;
                        _searchController.clear();
                        _search = null;
                      }),
                    ),
                    _ModeChip(
                      label: 'Webshop',
                      selected: effectiveMode == _ShopMode.webshop,
                      onTap: () => setState(() {
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
                  ],
                ),
              ),
            ),
          // Search field
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchController,
              onChanged:
                  effectiveMode == _ShopMode.marketplace && _showFavorites
                  ? null
                  : _onSearchChanged,
              enabled:
                  !(effectiveMode == _ShopMode.marketplace && _showFavorites),
              decoration: InputDecoration(
                hintText: effectiveMode == _ShopMode.marketplace
                    ? (_showFavorites
                          ? 'Search disabled in favorites'
                          : 'Search marketplace')
                    : 'Search webshop',
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppColors.onSurfaceVariant,
                ),
                suffixIcon: _search != null
                    ? IconButton(
                        onPressed: () {
                          AppLogger.info(
                            '[MARKETPLACE_SCREEN] Search cleared',
                            extra: {
                              'previous_search': _search,
                              'mode': effectiveMode.name,
                            },
                          );
                          _searchController.clear();
                          setState(() => _search = null);
                        },
                        icon: const Icon(
                          Icons.clear,
                          color: AppColors.onSurfaceVariant,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: AppColors.gray50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: AppColors.defaultBlue,
                    width: 2,
                  ),
                ),
              ),
              textInputAction: TextInputAction.search,
            ),
          ),

          // Category Filter – premium pill row (marketplace only)
          if (effectiveMode == _ShopMode.marketplace)
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                itemBuilder: (_, i) {
                  final cat = _categories[i];
                  final selected = cat == _selectedCategory;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.subtleBlue
                            : theme.colorScheme.surface,
                        border: Border.all(
                          color: selected
                              ? AppColors.defaultBlue
                              : AppColors.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: Text(
                          _getCategoryDisplayName(cat),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: selected
                                ? AppColors.defaultBlue
                                : AppColors.charcoalBlack,
                            fontWeight: FontWeight.w600,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                  );
                },
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemCount: _categories.length,
              ),
            ),

          const Divider(height: 1),

          // Products Grid
          Expanded(
            child: (effectiveMode == _ShopMode.marketplace ? productsAsync : webshopAsync)
                .when(
                  data: (products) {
                    final visibleProducts = effectiveMode == _ShopMode.webshop
                        ? _computeWebshopList(products as List<WebshopProduct>)
                        : products;
                    _logProductsUiState(
                      mode: effectiveMode,
                      campusId: campus.id,
                      campusName: campus.name,
                      visibleCount: visibleProducts.length,
                    );

                    return visibleProducts.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _showFavorites
                                      ? Icons.favorite_border
                                      : Icons.shopping_bag_outlined,
                                  size: 64,
                                  color: AppColors.onSurfaceVariant,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _showFavorites
                                      ? 'No favorites yet'
                                      : 'No items found',
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _showFavorites
                                      ? 'Heart items you like to see them here!'
                                      : 'Try changing your filter or check back later',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 14,
                                  mainAxisSpacing: 14,
                                  childAspectRatio: 0.72,
                                ),
                            controller: _scrollController,
                            itemCount: (effectiveMode == _ShopMode.webshop)
                                ? _computeWebshopList(
                                        products as List<WebshopProduct>,
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
                                );
                                if (index >= list.length) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                return _WebshopProductCard(
                                  product: list[index],
                                );
                              }
                            },
                          );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
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
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: AppColors.error,
                            size: 48,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Failed to load',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            e.toString(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () {
                              if (effectiveMode == _ShopMode.marketplace) {
                                ref.invalidate(productsProvider(query));
                              } else {
                                ref.invalidate(
                                  webshopProductsProvider(webshopQuery),
                                );
                              }
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try again'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
      floatingActionButton: effectiveMode == _ShopMode.marketplace
          ? FloatingActionButton.extended(
              onPressed: () => context.go('/explore/products/new'),
              icon: const Icon(Icons.add),
              label: const Text('Sell Item'),
              backgroundColor: AppColors.green9,
            )
          : null,
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

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.surface
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: AppColors.shadowLight,
                      blurRadius: 10,
                      offset: Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.defaultBlue : AppColors.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WebshopProductCard extends StatelessWidget {
  final WebshopProduct product;

  const _WebshopProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSale = product.hasSale;
    final priceText = hasSale
        ? 'NOK ${product.salePrice}'
        : 'NOK ${product.price}';

    return InkWell(
      onTap: () {
        context.pushNamed(
          'webshop-product-detail',
          pathParameters: {'productId': product.id.toString()},
          extra: product,
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowLight,
              blurRadius: 16,
              offset: Offset(0, 10),
            ),
          ],
          border: Border.all(color: AppColors.gray100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      child: product.images.isNotEmpty
                          ? Image.network(
                              product.images.first,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: AppColors.gray100,
                                child: const Icon(Icons.image_outlined),
                              ),
                            )
                          : Container(
                              color: AppColors.gray100,
                              child: const Icon(
                                Icons.shopping_bag,
                                size: 48,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        children: [
                          if (hasSale) ...[
                            Text(
                              'NOK ${product.price}',
                              style: const TextStyle(
                                color: Colors.white70,
                                decoration: TextDecoration.lineThrough,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            priceText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (hasSale)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'SALE',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
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
                    Expanded(
                      child: Text(
                        product.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (product.campusLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        product.campusLabel!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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
    final auth = ref.watch(authStateProvider);

    return InkWell(
      onTap: () => context.go('/explore/products/${widget.product.id}'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowLight,
              blurRadius: 16,
              offset: Offset(0, 10),
            ),
          ],
          border: Border.all(color: AppColors.gray100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with overlay badges
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      child: widget.product.images.isNotEmpty
                          ? Image.network(
                              widget.product.images.first,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: AppColors.gray100,
                                child: const Icon(Icons.image_outlined),
                              ),
                            )
                          : Container(
                              color: AppColors.gray100,
                              child: Icon(
                                _getCategoryIcon(widget.product.category),
                                size: 48,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                    ),
                  ),
                  // Price pill
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'NOK ${widget.product.price.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  // Functional favorite icon
                  if (auth.isAuthenticated)
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: GestureDetector(
                        onTap: _toggleFavorite,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(
                                color: AppColors.shadowLight,
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: _favoriteLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.defaultBlue,
                                  ),
                                )
                              : Icon(
                                  _isFavorited
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: _isFavorited
                                      ? AppColors.error
                                      : AppColors.defaultBlue,
                                  size: 20,
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Info - flexible content area
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.product.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.product.sellerName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.onSurfaceVariant,
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
                            color: _getConditionColor(
                              widget.product.condition,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            widget.product.displayCondition,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: _getConditionColor(
                                widget.product.condition,
                              ),
                              fontWeight: FontWeight.w600,
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

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'books':
        return Icons.book;
      case 'electronics':
        return Icons.devices;
      case 'furniture':
        return Icons.chair;
      case 'clothes':
        return Icons.checkroom;
      case 'sports':
        return Icons.sports;
      default:
        return Icons.shopping_bag;
    }
  }

  Color _getConditionColor(String condition) {
    switch (condition) {
      case 'new':
        return AppColors.success;
      case 'like_new':
        return AppColors.accentBlue;
      case 'good':
        return AppColors.defaultGold;
      case 'fair':
        return AppColors.orange9;
      case 'poor':
        return AppColors.error;
      default:
        return AppColors.onSurfaceVariant;
    }
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
