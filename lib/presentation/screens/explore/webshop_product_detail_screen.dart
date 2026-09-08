import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/product_custom_field.dart';
import '../../../data/models/product_variation.dart';
import '../../../data/models/webshop_product_model.dart';
import '../../../data/services/webshop_service.dart';
import '../../../providers/ui/locale_provider.dart';
import '../../widgets/premium/premium_html_renderer.dart';

/// Product detail screen for a webshop item.
///
/// Either [product] is supplied directly (the usual case — callers already
/// hold the product from a list) or [productId] is supplied and the screen
/// fetches it itself. The latter covers deep links that only carry a path
/// parameter, such as [ShowcaseNavigationService]'s CTA handling.
class WebshopProductDetailScreen extends ConsumerStatefulWidget {
  final WebshopProduct? product;
  final String? productId;

  const WebshopProductDetailScreen({super.key, this.product, this.productId})
    : assert(
        product != null || productId != null,
        'WebshopProductDetailScreen requires either a product or a productId',
      );

  @override
  ConsumerState<WebshopProductDetailScreen> createState() =>
      _WebshopProductDetailScreenState();
}

class _WebshopProductDetailScreenState
    extends ConsumerState<WebshopProductDetailScreen> {
  int _currentImageIndex = 0;
  int _selectedVariationIndex = 0;

  WebshopProduct? _product;
  bool _loading = false;
  String? _error;

  final _formKey = GlobalKey<FormState>();

  /// Text/textarea/number/email controllers, keyed by `fieldKey`.
  final Map<String, TextEditingController> _textControllers = {};

  /// Selected option for `select` fields, keyed by `fieldKey`.
  final Map<String, String?> _selectValues = {};

  /// Collected custom-field values, keyed by `fieldKey`. This is populated
  /// once validation passes and is kept in screen state only — nothing here
  /// is submitted anywhere. Order/checkout submission is out of scope.
  final Map<String, dynamic> _customFieldValues = {};

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    if (product != null) {
      _product = product;
      _initFieldState(product);
    } else {
      _loadProduct();
    }
  }

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProduct() async {
    final productId = widget.productId;
    if (productId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final locale = ref.read(localeProvider).languageCode;
      final service = WebshopService();
      final product = await service.getProductById(productId, locale: locale);

      if (!mounted) return;

      if (product == null) {
        setState(() {
          _loading = false;
          _error = 'This product could not be found.';
        });
        return;
      }

      _initFieldState(product);
      setState(() {
        _product = product;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load this product: $e';
      });
    }
  }

  /// Resets selection/controller state for a freshly loaded [product].
  void _initFieldState(WebshopProduct product) {
    _selectedVariationIndex = 0;

    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    _textControllers.clear();
    _selectValues.clear();
    _customFieldValues.clear();

    for (final field in product.customFields) {
      if (field.type == 'select') {
        _selectValues[field.fieldKey] = null;
      } else {
        _textControllers[field.fieldKey] = TextEditingController();
      }
    }
  }

  /// The currently selected variation, or null when the product has none.
  ProductVariation? get _selectedVariation {
    final product = _product;
    if (product == null || product.variations.isEmpty) return null;
    if (_selectedVariationIndex < 0 ||
        _selectedVariationIndex >= product.variations.length) {
      return null;
    }
    return product.variations[_selectedVariationIndex];
  }

  void _handleContinue() {
    final isValid = _formKey.currentState?.validate() ?? true;
    if (!isValid) return;

    final product = _product;
    if (product != null) {
      for (final field in product.customFields) {
        _customFieldValues[field.fieldKey] = field.type == 'select'
            ? _selectValues[field.fieldKey]
            : _textControllers[field.fieldKey]?.text.trim();
      }
    }

    // Orders/checkout are out of scope for this migration. Values are kept
    // in `_customFieldValues`, keyed by fieldKey, ready for a future
    // checkout flow — nothing is submitted here.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Checkout is coming soon')),
    );
  }

  Widget _buildBackButton(bool isDark) {
    return IconButton(
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
    );
  }

  PreferredSizeWidget _buildSimpleAppBar(ThemeData theme, bool isDark) {
    return AppBar(
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
      elevation: 0,
      leading: _buildBackButton(isDark),
      title: Text(
        'BISO Shop',
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: isDark ? AppColors.onSurfaceDark : AppColors.onSurface,
        ),
      ),
      centerTitle: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_loading) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        appBar: _buildSimpleAppBar(theme, isDark),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final product = _product;
    if (product == null) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        appBar: _buildSimpleAppBar(theme, isDark),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.error,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  'Failed to load product',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _error ?? 'Something went wrong.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _loadProduct,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final variations = product.variations;
    final selectedVariation = _selectedVariation;
    final displayPrice = selectedVariation?.regularPrice ?? product.regularPrice;
    final displayMemberPrice = selectedVariation?.memberPrice;

    return Scaffold(
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: CustomScrollView(
          slivers: [
            // App Bar
            SliverAppBar(
              backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
              elevation: 0,
              pinned: true,
              expandedHeight: 0,
              leading: _buildBackButton(isDark),
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
                    product.title ?? '',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.charcoalBlack,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Price Section
                  Text(
                    'NOK ${displayPrice.toStringAsFixed(0)}',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.defaultBlue,
                    ),
                  ),
                  if (displayMemberPrice != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Member price: NOK ${displayMemberPrice.toStringAsFixed(0)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.strongGold,
                      ),
                    ),
                  ],

                  // Variation selector
                  if (variations.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Options',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.charcoalBlack,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(variations.length, (index) {
                        final variation = variations[index];
                        final selected = index == _selectedVariationIndex;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedVariationIndex = index;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.defaultBlue
                                  : AppColors.subtleBlue.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: selected
                                    ? AppColors.defaultBlue
                                    : AppColors.gray100,
                              ),
                            ),
                            child: Text(
                              variation.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? Colors.white
                                    : AppColors.charcoalBlack,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Description
                  if (product.description != null &&
                      product.description!.isNotEmpty) ...[
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
                      child: product.description!.toFullHtml(
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.charcoalBlack.withValues(alpha: 0.8),
                          height: 1.5,
                        ),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Custom fields
                  if (product.customFields.isNotEmpty) ...[
                    Text(
                      'Additional information',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.charcoalBlack,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final field in product.customFields)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildCustomField(field),
                      ),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: FilledButton.icon(
            onPressed: _handleContinue,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Continue'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppColors.defaultBlue,
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the input for one custom field, matching [field.type].
  ///
  /// `fieldKey` is an opaque id and is never rendered — only [field.label],
  /// [field.placeholder] and [field.helpText] are shown to the user.
  Widget _buildCustomField(ProductCustomField field) {
    final labelText = field.isRequired ? '${field.label} *' : field.label;
    final requiredValidator = field.isRequired
        ? (String? value) {
            if (value == null || value.trim().isEmpty) {
              return 'This field is required';
            }
            return null;
          }
        : null;

    switch (field.type) {
      case 'textarea':
        return TextFormField(
          controller: _textControllers[field.fieldKey],
          minLines: 3,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: labelText,
            hintText: field.placeholder,
            helperText: field.helpText,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          validator: requiredValidator,
        );
      case 'number':
        return TextFormField(
          controller: _textControllers[field.fieldKey],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: labelText,
            hintText: field.placeholder,
            helperText: field.helpText,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          validator: requiredValidator,
        );
      case 'email':
        return TextFormField(
          controller: _textControllers[field.fieldKey],
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: labelText,
            hintText: field.placeholder,
            helperText: field.helpText,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          validator: requiredValidator,
        );
      case 'select':
        // No live product currently has a `select` custom field (all live
        // fields are `text` with empty options), so this branch is
        // unverified against real data.
        return DropdownButtonFormField<String>(
          initialValue: _selectValues[field.fieldKey],
          decoration: InputDecoration(
            labelText: labelText,
            helperText: field.helpText,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          hint: field.placeholder != null ? Text(field.placeholder!) : null,
          items: field.options
              .map(
                (option) => DropdownMenuItem<String>(
                  value: option,
                  child: Text(option),
                ),
              )
              .toList(),
          onChanged: (value) {
            setState(() {
              _selectValues[field.fieldKey] = value;
            });
          },
          validator: field.isRequired
              ? (value) {
                  if (value == null || value.isEmpty) {
                    return 'This field is required';
                  }
                  return null;
                }
              : null,
        );
      case 'text':
      default:
        return TextFormField(
          controller: _textControllers[field.fieldKey],
          decoration: InputDecoration(
            labelText: labelText,
            hintText: field.placeholder,
            helperText: field.helpText,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          validator: requiredValidator,
        );
    }
  }
}
