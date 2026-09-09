import 'package:flutter/material.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../generated/l10n/app_localizations.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/large_event_model.dart';
import '../../data/models/campus_model.dart';
import '../../data/services/showcase_navigation_service.dart';
import '../../providers/campus/campus_provider.dart';
import '../../providers/notification/notification_provider.dart';

/// Dynamic hero carousel that can display different types of showcase content
class DynamicHeroCarousel extends ConsumerStatefulWidget {
  final CampusModel campus;
  final List<LargeEventModel> showcaseItems;
  final VoidCallback onCampusTap;
  final Duration autoAdvanceDuration;
  final bool enableAutoAdvance;

  const DynamicHeroCarousel({
    super.key,
    required this.campus,
    required this.showcaseItems,
    required this.onCampusTap,
    this.autoAdvanceDuration = const Duration(seconds: 5),
    this.enableAutoAdvance = true,
  });

  @override
  ConsumerState<DynamicHeroCarousel> createState() => _DynamicHeroCarouselState();
}

class _DynamicHeroCarouselState extends ConsumerState<DynamicHeroCarousel>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  Timer? _autoAdvanceTimer;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    // Start fade-in animation
    _fadeController.forward();

    // Setup auto-advance timer if enabled and we have multiple items
    final totalItems = 1 + widget.showcaseItems.length;
    if (widget.enableAutoAdvance && totalItems > 1) {
      _startAutoAdvance();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeController.dispose();
    _autoAdvanceTimer?.cancel();
    super.dispose();
  }

  String _getCampusImagePath(String campusId) {
    switch (campusId) {
      case '1': // Oslo
        return 'assets/images/campus/oslo.png';
      case '2': // Bergen
        return 'assets/images/campus/bergen.png';
      case '3': // Trondheim
        return 'assets/images/campus/trondheim.png';
      case '4': // Stavanger
        return 'assets/images/campus/stavanger.png';
      case '5': // National
        return 'assets/images/campus/oslo.png'; // Use Oslo as fallback
      default:
        return 'assets/images/campus/oslo.png'; // Default fallback
    }
  }

  void _startAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer.periodic(widget.autoAdvanceDuration, (_) {
      final totalItems = 1 + widget.showcaseItems.length;
      if (mounted && totalItems > 1) {
        final nextIndex = (_currentIndex + 1) % totalItems;
        _pageController.animateToPage(
          nextIndex,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _stopAutoAdvance() {
    _autoAdvanceTimer?.cancel();
  }

  void _resumeAutoAdvance() {
    final totalItems = 1 + widget.showcaseItems.length;
    if (widget.enableAutoAdvance && totalItems > 1) {
      _startAutoAdvance();
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final isInitialized = ref.watch(campusInitializedProvider);
    
    // Show loading state until campus is properly initialized
    if (!isInitialized) {
      return SizedBox(
        height: 400 + statusBarHeight,
        child: _buildLoadingSkeleton(statusBarHeight),
      );
    }
    
    // Show carousel once campus is initialized
    return SizedBox(
      height: 400 + statusBarHeight,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: _buildCarouselView(statusBarHeight),
      ),
    );
  }

  Widget _buildLoadingSkeleton(double statusBarHeight) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.gray200,
            AppColors.gray300,
            AppColors.gray400,
          ],
          stops: const [0.0, 0.7, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Content placeholder
          Positioned(
            top: statusBarHeight + 20,
            left: 24,
            right: 24,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header placeholder
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 120,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    Container(
                      width: 80,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 40),

                // Title placeholder
                Container(
                  width: double.infinity,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),

                const SizedBox(height: 16),

                // Subtitle placeholder
                Container(
                  width: MediaQuery.of(context).size.width * 0.7,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                const SizedBox(height: 32),

                // Button placeholder
                Container(
                  width: 140,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarouselView(double statusBarHeight) {
    // Total items = 1 default hero + showcase items
    final totalItems = 1 + widget.showcaseItems.length;
    
    if (totalItems == 1) {
      // Only default hero - no carousel needed
      return _buildDefaultHero(statusBarHeight);
    }

    return Stack(
      children: [
        // Page view for carousel
        GestureDetector(
          onPanDown: (_) => _stopAutoAdvance(),
          onPanEnd: (_) => _resumeAutoAdvance(),
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemCount: totalItems,
            itemBuilder: (context, index) {
              if (index == 0) {
                // First item is always the default hero
                return _buildDefaultHero(statusBarHeight, showCampusButton: false);
              } else {
                // Subsequent items are showcase items
                return _buildShowcaseCard(widget.showcaseItems[index - 1], statusBarHeight, showCampusButton: false);
              }
            },
          ),
        ),

        // Fixed campus switcher (always visible)
        Positioned(
          top: statusBarHeight + 20,
          right: 24,
          child: _CampusButton(campus: widget.campus, onTap: widget.onCampusTap),
        ),

        // Page indicators
        if (totalItems > 1)
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: _buildPageIndicators(totalItems),
          ),
      ],
    );
  }

  Widget _buildShowcaseCard(LargeEventModel item, double statusBarHeight, {bool showCampusButton = true}) {
    return ShowcaseHeroCard(
      item: item,
      campus: widget.campus,
      statusBarHeight: statusBarHeight,
      onCampusTap: widget.onCampusTap,
      showCampusButton: showCampusButton,
    );
  }

  Widget _buildDefaultHero(double statusBarHeight, {bool showCampusButton = true}) {
    final l10n = AppLocalizations.of(context)!;
    // Default campus hero when no showcase items
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.biLightBlue,
            AppColors.biNavy,
            AppColors.charcoalBlack,
          ],
          stops: const [0.0, 0.7, 1.0],
        ),
        image: DecorationImage(
          image: AssetImage(_getCampusImagePath(widget.campus.id)),
          fit: BoxFit.cover,
          opacity: 0.3,
        ),
      ),
      child: Stack(
        children: [
          // Decorative elements
          _buildDecorationElements(statusBarHeight),
          
          // Main content
          Positioned(
            top: statusBarHeight + 20,
            left: 24,
            right: 24,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with campus switcher
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'Welcome to BISO',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _NotificationBellButton(),
                        if (showCampusButton) ...[
                          const SizedBox(width: 8),
                          _CampusButton(
                            campus: widget.campus,
                            onTap: widget.onCampusTap,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Campus info
                Expanded(
                  child: GestureDetector(
                    onTap: () => context.push('/explore/campus/${widget.campus.id}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.campus.name,
                          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),

                        const SizedBox(height: 12),

                        Text(
                          l10n.connectingStudentsMessage,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                            height: 1.4,
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Campus Detail Button
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => context.push('/explore/campus/${widget.campus.id}'),
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      l10n.exploreCampusMessage,
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.arrow_forward_ios,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDecorationElements(double statusBarHeight) {
    return Stack(
      children: [
        Positioned(
          top: statusBarHeight + 60,
          right: -50,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.1),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 80,
          left: -80,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.biLightBlue.withValues(alpha: 0.2),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPageIndicators(int totalItems) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        totalItems,
        (index) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: _currentIndex == index ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: _currentIndex == index
                ? Colors.white
                : Colors.white.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

/// Individual showcase hero card that handles different content types
class ShowcaseHeroCard extends StatelessWidget {
  final LargeEventModel item;
  final CampusModel campus;
  final double statusBarHeight;
  final VoidCallback onCampusTap;
  final bool showCampusButton;

  const ShowcaseHeroCard({
    super.key,
    required this.item,
    required this.campus,
    required this.statusBarHeight,
    required this.onCampusTap,
    this.showCampusButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Get gradient colors with fallback
    final gradientColors = item.gradientColors.isNotEmpty 
      ? item.gradientColors 
      : [
          AppColors.biLightBlue,
          AppColors.biNavy,
          AppColors.charcoalBlack,
        ];
    
    // Generate appropriate stops based on number of colors
    List<double>? stops;
    if (gradientColors.length == 2) {
      stops = [0.0, 1.0];
    } else if (gradientColors.length == 3) {
      stops = [0.0, 0.7, 1.0];
    }
    // For other lengths, let Flutter handle it automatically
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
          stops: stops,
        ),
      ),
      child: Stack(
        children: [
          // Background image if provided
          if (item.backgroundImageUrl != null)
            Positioned.fill(
              child: Image.network(
                item.backgroundImageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
              ),
            ),

          // Dark overlay for better text readability
          if (item.backgroundImageUrl != null)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.3),
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
              ),
            ),

          // Decorative elements
          _buildDecorationElements(),
          
          // Main content
          Positioned(
            top: statusBarHeight + 20,
            left: 24,
            right: 24,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with optional campus switcher
                Row(
                  mainAxisAlignment: showCampusButton ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Text(
                        _getShowcaseTypeLabel(context),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (showCampusButton) _CampusButton(campus: campus, onTap: onCampusTap),
                  ],
                ),

                const SizedBox(height: 16),

                // Content area
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo if provided
                      if (item.logoUrl != null) ...[
                        Image.network(
                          item.logoUrl!,
                          height: 60,
                          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Title
                      Text(
                        item.name,
                        style: theme.textTheme.displayMedium?.copyWith(
                          color: item.textColor,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Description
                      Text(
                        item.description,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),

                      const SizedBox(height: 20),

                      // CTA Button
                      _buildCTAButton(context),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getShowcaseTypeLabel(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (item.showcaseType) {
      case ShowcaseType.webshopProduct:
        return l10n.featuredProductMessage;
      case ShowcaseType.externalEvent:
        return l10n.specialEventMessage;
      case ShowcaseType.jobOpportunity:
        return l10n.featuredOpportunityMessage;
      case ShowcaseType.announcement:
        return l10n.importantAnnouncementMessage;
      case ShowcaseType.largeEvent:
        return l10n.featuredEventMessage;
    }
  }

  Widget _buildCTAButton(BuildContext context) {
    return InkWell(
      onTap: () => _handleCTAPress(context),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.effectiveCtaText,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.charcoalBlack,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_rounded,
              color: AppColors.charcoalBlack,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _handleCTAPress(BuildContext context) async {
    await ShowcaseNavigationService().handleShowcaseCTA(context, item);
  }

  Widget _buildDecorationElements() {
    return Stack(
      children: [
        Positioned(
          top: statusBarHeight + 60,
          right: -50,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.1),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 80,
          left: -80,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  item.primaryColor.withValues(alpha: 0.2),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Campus button widget for switching campuses
/// Bell button shown in the hero header with an unread badge driven by
/// [unreadCountProvider]. Opens the in-app notifications inbox.
class _NotificationBellButton extends ConsumerWidget {
  const _NotificationBellButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadCountProvider);

    return Material(
      color: Colors.white.withValues(alpha: 0.15),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/notifications'),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(
                Icons.notifications_none_rounded,
                color: Colors.white,
                size: 22,
              ),
              if (unreadCount > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(minWidth: 16),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: Text(
                      unreadCount > 9 ? '9+' : '$unreadCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CampusButton extends StatelessWidget {
  final CampusModel campus;
  final VoidCallback onTap;

  const _CampusButton({required this.campus, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on_rounded, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              campus.name,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.expand_more,
              size: 16,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ],
        ),
      ),
    );
  }
}