import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/webshop_product_model.dart';
import '../../widgets/premium/premium_html_renderer.dart';

class WebshopProductDetailScreen extends StatefulWidget {
  final WebshopProduct product;

  const WebshopProductDetailScreen({
    super.key,
    required this.product,
  });

  @override
  State<WebshopProductDetailScreen> createState() => _WebshopProductDetailScreenState();
}

class _WebshopProductDetailScreenState extends State<WebshopProductDetailScreen> {
  int _currentImageIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = widget.product;
    final hasSale = product.hasSale;
    final regularPrice = double.tryParse(product.price) ?? 0.0;
    final salePrice = double.tryParse(product.salePrice) ?? 0.0;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
      body: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
            backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
            elevation: 0,
            pinned: true,
            expandedHeight: 0,
            leading: IconButton(
              onPressed: () => NavigationUtils.safeGoBack(context),
              icon: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.arrow_back,
                  color: isDark ? AppColors.onSurfaceDark : AppColors.onSurface,
                  size: 20,
                ),
              ),
            ),
            title: Text(
              'BISO Shop',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.onSurfaceDark : AppColors.onSurface,
              ),
            ),
            centerTitle: true,
          ),

          // Product Images
          SliverToBoxAdapter(
            child: SizedBox(
              height: 300,
              child: product.images.isEmpty
                  ? Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppColors.gray100,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.image_outlined,
                          size: 64,
                          color: AppColors.charcoalBlack,
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        // Main Image
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            child: PageView.builder(
                              onPageChanged: (index) {
                                setState(() {
                                  _currentImageIndex = index;
                                });
                              },
                              itemCount: product.images.length,
                              itemBuilder: (context, index) {
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.network(
                                    product.images[index],
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        decoration: BoxDecoration(
                                          color: AppColors.gray100,
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: const Center(
                                          child: Icon(
                                            Icons.broken_image_outlined,
                                            size: 64,
                                            color: AppColors.charcoalBlack,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        
                        // Image Indicators
                        if (product.images.length > 1) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              product.images.length,
                              (index) => Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _currentImageIndex == index
                                      ? AppColors.defaultBlue
                                      : AppColors.gray100,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),

          // Product Details
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Product Name
                Text(
                  product.name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.charcoalBlack,
                  ),
                ),

                const SizedBox(height: 8),

                // Campus & Department Info
                if (product.campusLabel != null || product.departmentLabel != null)
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (product.campusLabel != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.defaultBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.defaultBlue.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            product.campusLabel!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.defaultBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (product.departmentLabel != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accentGold.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.defaultGold.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            product.departmentLabel!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.strongGold,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),

                const SizedBox(height: 16),

                // Price Section
                Row(
                  children: [
                    if (hasSale) ...[
                      Text(
                        'NOK ${salePrice.toStringAsFixed(0)}',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.defaultBlue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'NOK ${regularPrice.toStringAsFixed(0)}',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          decoration: TextDecoration.lineThrough,
                          color: AppColors.charcoalBlack.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'SALE',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ] else
                      Text(
                        'NOK ${regularPrice.toStringAsFixed(0)}',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.defaultBlue,
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 24),

                // Description
                if (product.htmlDescription != null &&
                    product.htmlDescription!.isNotEmpty) ...[
                  Text(
                    'Description',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.charcoalBlack,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.subtleBlue.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.gray100,
                      ),
                    ),
                    child: product.htmlDescription!.toFullHtml(
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.charcoalBlack.withValues(alpha: 0.8),
                        height: 1.5,
                      ),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}