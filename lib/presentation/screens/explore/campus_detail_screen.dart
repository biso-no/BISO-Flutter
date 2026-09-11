import '../../../core/theme/biso_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/campus/campus_provider.dart';
import 'campus_detail_components.dart';

class CampusDetailScreen extends ConsumerStatefulWidget {
  final String campusId;

  const CampusDetailScreen({super.key, required this.campusId});

  @override
  ConsumerState<CampusDetailScreen> createState() => _CampusDetailScreenState();
}

class _CampusDetailScreenState extends ConsumerState<CampusDetailScreen>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  
  bool _showFloatingHeader = false;

  @override
  void initState() {
    super.initState();
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeOut));

    _scrollController.addListener(_onScroll);
    
    // Start animations
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fadeController.forward();
      _scaleController.forward();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fadeController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  void _onScroll() {
    const threshold = 200.0;
    final shouldShow = _scrollController.offset > threshold;
    
    if (shouldShow != _showFloatingHeader) {
      setState(() {
        _showFloatingHeader = shouldShow;
      });
    }
  }

  void _navigateToExplore(String category) {
    switch (category) {
      case 'events':
        context.push('/explore/events');
        break;
      case 'products':
        context.push('/explore/products');
        break;
      case 'jobs':
        context.push('/explore/volunteer');
        break;
      case 'units':
        context.push('/explore/units');
        break;
      default:
        context.push('/explore');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final campusAsync = ref.watch(campusProvider(widget.campusId));

    return campusAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(
          title: Text(l10n.campusMessage),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => NavigationUtils.goBackSafely(context),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        appBar: AppBar(
          title: Text(l10n.campusMessage),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => NavigationUtils.goBackSafely(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Error loading campus',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.disabledColor,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
      data: (campus) {
        if (campus == null) {
          return Scaffold(
            appBar: AppBar(
              title: Text(l10n.campusMessage),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => NavigationUtils.goBackSafely(context),
              ),
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.location_off,
                    size: 64,
                    color: theme.disabledColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Campus not found',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The requested campus could not be found.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.disabledColor,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          body: AnimatedBuilder(
            animation: _fadeAnimation,
            builder: (context, child) {
              return FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      // Premium Parallax Header
                      CampusParallaxHeader(
                        campus: campus,
                        onBackPressed: () =>
                            NavigationUtils.goBackSafely(context),
                      ),

                      // Quick Actions
                      SliverToBoxAdapter(
                        child: Transform.translate(
                          offset: const Offset(0, -30),
                          child: CampusQuickActions(
                            onActionTap: _navigateToExplore,
                          ),
                        ),
                      ),

                      // Content
                      SliverPadding(
                        padding: BisoNavigationInset.padding(
                          context,
                          const EdgeInsets.fromLTRB(24, 0, 24, 88),
                        ),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            const SizedBox(height: 16),

                            // Benefit Cards
                            CampusBenefitCard(
                              title: l10n.forStudentsMessage,
                              benefits: campus.studentBenefits,
                              icon: Icons.school_outlined,
                              color: AppColors.defaultBlue,
                              animationDelay: 200,
                            ),

                            const SizedBox(height: 24),

                            CampusBenefitCard(
                              title: l10n.forBusinessMessage,
                              benefits: campus.businessBenefits,
                              icon: Icons.business_outlined,
                              color: AppColors.accentBlue,
                              animationDelay: 400,
                            ),

                            const SizedBox(height: 24),

                            CampusBenefitCard(
                              title: l10n.careerAdvantagesMessage,
                              benefits: campus.careerAdvantages,
                              icon: Icons.trending_up_outlined,
                              color: AppColors.strongGold,
                              animationDelay: 600,
                            ),

                            const SizedBox(height: 32),

                            // Department Members Showcase
                            CampusDepartmentShowcase(
                              campusId: campus.id,
                              animationDelay: 800,
                            ),

                            const SizedBox(height: 32),

                            // Contact Information
                            CampusContactCard(
                              campus: campus,
                              animationDelay: 1000,
                            ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Floating Header
          floatingActionButton: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _showFloatingHeader
                ? Container(
                    key: const ValueKey('floating_header'),
                    margin: EdgeInsets.only(
                      bottom: BisoNavigationInset.of(context),
                    ),
                    child: FloatingActionButton.extended(
                      onPressed: () {
                        _scrollController.animateTo(
                          0,
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOut,
                        );
                      },
                      backgroundColor: AppColors.defaultBlue,
                      foregroundColor: Colors.white,
                      icon: const Icon(Icons.keyboard_arrow_up),
                      label: Text(campus.name),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('no_header')),
          ),
        );
      },
    );
  }
}