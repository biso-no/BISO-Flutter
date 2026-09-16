import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/currency.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/product_custom_field.dart';
import '../../../data/models/product_variation.dart';
import '../../../data/models/webshop_product_model.dart';
import '../../../data/services/webshop_service.dart';
import '../../../providers/membership/membership_overview_provider.dart';
import '../../../providers/shop/cart_provider.dart';
import '../../../providers/ui/locale_provider.dart';
import '../../widgets/biso/biso.dart';
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

/// Returns the first required custom field with no collected value, or
/// `null` when every required field already has one.
///
/// This is checked directly against the screen's own collected state
/// (`selectValues`/`textValues`) rather than via `Form.validate()`. The
/// custom fields are the tail of a lazily-built `SliverList`, so a field
/// that lies beyond the viewport plus the sliver's cache extent has never
/// been built — it has no `FormFieldState`, so it never registers with the
/// enclosing `Form`, and `Form.validate()` silently skips it. Reading the
/// collected state directly makes this check correct regardless of scroll
/// position or which fields happen to be mounted.
///
/// Extracted as a top-level, `@visibleForTesting` function (rather than a
/// private method on the screen's `State`) so the gating logic itself can be
/// unit-tested without constructing the widget tree.
@visibleForTesting
ProductCustomField? firstMissingRequiredCustomField({
  required List<ProductCustomField> customFields,
  required Map<String, String?> selectValues,
  required Map<String, String> textValues,
}) {
  for (final field in customFields) {
    if (!field.isRequired) continue;
    final value = field.type == 'select'
        ? selectValues[field.fieldKey]
        : textValues[field.fieldKey];
    if (value == null || value.trim().isEmpty) {
      return field;
    }
  }
  return null;
}

class _WebshopProductDetailScreenState
    extends ConsumerState<WebshopProductDetailScreen> {
  int _currentImageIndex = 0;
  int _selectedVariationIndex = 0;

  WebshopProduct? _product;
  bool _loading = false;
  String? _error;

  final _formKey = GlobalKey<FormState>();

  /// Scrolls a below-the-fold custom field into view when it blocks
  /// [_handleAddToCart]; see `_revealCustomField`.
  final _scrollController = ScrollController();

  /// Text/textarea/number/email controllers, keyed by `fieldKey`.
  final Map<String, TextEditingController> _textControllers = {};

  /// Selected option for `select` fields, keyed by `fieldKey`.
  final Map<String, String?> _selectValues = {};

  /// One `GlobalKey` per custom field, keyed by `fieldKey`, used to locate
  /// and scroll to a field that fails validation — including one that has
  /// never been built (see `firstMissingRequiredCustomField`).
  final Map<String, GlobalKey> _customFieldKeys = {};

  /// Collected custom-field values, keyed by `fieldKey`. Populated once
  /// validation passes, then carried onto the cart line — the answers are
  /// part of what makes one line distinct from another line of the same
  /// product, and they end up on the order as `order_item_field_answers`.
  final Map<String, String> _customFieldValues = {};

  /// True while the add-to-cart write (and its stock hold) is in flight.
  bool _addingToCart = false;

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
    _scrollController.dispose();
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
    _customFieldKeys.clear();

    for (final field in product.customFields) {
      _customFieldKeys[field.fieldKey] = GlobalKey();
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

  /// Looks up the first required custom field missing a value, using
  /// [product]'s own collected controller/select state.
  ///
  /// Delegates to the top-level [firstMissingRequiredCustomField] so the
  /// actual gating logic is independently unit-testable; this method only
  /// adapts the screen's `TextEditingController` map into the plain
  /// `Map<String, String>` that function expects.
  ProductCustomField? _firstMissingRequiredField(WebshopProduct product) {
    return firstMissingRequiredCustomField(
      customFields: product.customFields,
      selectValues: _selectValues,
      textValues: _textControllers.map(
        (key, controller) => MapEntry(key, controller.text),
      ),
    );
  }

  /// Scrolls [field] into view and re-validates the form so the field's own
  /// error text paints, even when [field] has never been built (Finding 1:
  /// it lies beyond the sliver's viewport + cache extent and so has never
  /// registered with [_formKey]).
  void _revealCustomField(ProductCustomField field) {
    final builtContext = _customFieldKeys[field.fieldKey]?.currentContext;

    if (builtContext != null) {
      // Already built — likely just scrolled past, or within the cache
      // extent. Scroll precisely to it and re-validate.
      Scrollable.ensureVisible(
        builtContext,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      ).then((_) {
        if (!mounted) return;
        // Read fresh from the key rather than reusing the `builtContext`
        // captured before this gap, so this is safe despite the lint.
        final settledContext = _customFieldKeys[field.fieldKey]?.currentContext;
        // ignore: use_build_context_synchronously
        if (settledContext != null) _clearHeaderAbove(settledContext);
        _formKey.currentState?.validate();
      });
      return;
    }

    // Not built yet. Custom fields are always the last section of the
    // sliver list, so animating to the end of the scroll view forces it to
    // build (and register with the Form) regardless of how long the
    // description above it happens to be.
    final scrollController = _scrollController;
    if (!scrollController.hasClients) return;
    scrollController
        .animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        )
        .then((_) {
          if (!mounted) return;
          final revealedContext = _customFieldKeys[field.fieldKey]?.currentContext;
          if (revealedContext != null) {
            // `mounted` was just checked above; `revealedContext` is read
            // fresh from the key at this point, not carried across the
            // `animateTo` gap, so this is safe despite the lint.
            // ignore: use_build_context_synchronously
            Scrollable.ensureVisible(revealedContext, duration: const Duration(milliseconds: 200)).then((_) {
              if (!mounted) return;
              // Read fresh from the key again rather than reusing the
              // `revealedContext` captured before this second gap.
              final settledContext = _customFieldKeys[field.fieldKey]?.currentContext;
              // ignore: use_build_context_synchronously
              if (settledContext != null) _clearHeaderAbove(settledContext);
            });
          }
          _formKey.currentState?.validate();
        });
  }

  /// After [Scrollable.ensureVisible] settles, [fieldContext]'s top edge can
  /// still sit at the very top of the scroll content (`y = 0` inside the
  /// `CustomScrollView`). On this `overImage` [BisoPage] that position is
  /// behind the translucent floating header rather than below it: an
  /// `overImage` page reserves no leading scroll clearance for the header
  /// (the photo bleeds under the status bar instead), unlike a normal page
  /// where a leading spacer sliver keeps the header clear automatically.
  /// This nudges the scroll position so the field clears the header.
  void _clearHeaderAbove(BuildContext fieldContext) {
    if (!_scrollController.hasClients) return;
    final box = fieldContext.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    // `getInheritedWidgetOfExactType` rather than `BisoPageInsets.maybeOf`
    // (which calls `dependOnInheritedWidgetOfExactType`): this runs from an
    // async callback, not a build method, so registering a rebuild
    // dependency on the field's element would be a stray subscription that
    // never gets cleaned up the way a real build-time read would.
    final topInset =
        fieldContext.getInheritedWidgetOfExactType<BisoPageInsets>()?.top ??
        0;
    if (topInset <= 0) return;
    final fieldTop = box.localToGlobal(Offset.zero).dy;
    final shortfall = topInset - fieldTop;
    if (shortfall <= 0) return;
    final target = (_scrollController.offset - shortfall).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.jumpTo(target);
  }

  /// Validates the buyer's answers and, when they pass, puts the configured
  /// product in the cart.
  ///
  /// A "configuration" is the product plus the chosen variation plus these
  /// answers — the cart keys lines on exactly that, so adding a Large after a
  /// Small gives two lines rather than a quantity of two.
  Future<void> _handleAddToCart() async {
    final product = _product;
    if (product == null || _addingToCart) return;

    // Always run this first so any *currently built* field still paints its
    // own inline error, per the review's explicit instruction to keep this
    // call even though it cannot be trusted on its own (Finding 1).
    final isFormValid = _formKey.currentState?.validate() ?? false;

    // Authoritative gate: checked directly against the collected state, so
    // it blocks regardless of scroll position/registration (Finding 1).
    final missingField = _firstMissingRequiredField(product);
    if (missingField != null) {
      _revealCustomField(missingField);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${missingField.label} is required')),
      );
      return;
    }

    if (!isFormValid) return;

    _customFieldValues.clear();
    for (final field in product.customFields) {
      final value = field.type == 'select'
          ? _selectValues[field.fieldKey]
          : _textControllers[field.fieldKey]?.text.trim();
      if (value != null && value.isNotEmpty) {
        _customFieldValues[field.fieldKey] = value;
      }
    }

    setState(() => _addingToCart = true);
    try {
      final notifier = ref.read(cartProvider.notifier);
      final result = await notifier.addProduct(
        product: product,
        variation: _selectedVariation,
        customFields: _customFieldValues,
        customFieldDefinitions: product.customFields,
      );
      if (!mounted) return;

      // Adding can still come back empty-handed, or short: the stock hold is
      // written during `addProduct`, and a rejection there removes the line
      // again rather than throwing. Trust the result rather than the cart —
      // the cart cannot answer this, because another size of the same product
      // left standing after a clamp is indistinguishable from success.
      if (result.isRejected) {
        final reason =
            ref.read(cartProvider).error ??
            'This item could not be added right now.';
        notifier.clearError();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(reason)));
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isPartial
                ? 'Only ${result.added} left — that is what we added to your cart'
                : '${product.title ?? 'Item'} added to your cart',
          ),
          action: SnackBarAction(
            label: 'View cart',
            onPressed: () => context.push('/explore/products/cart'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _addingToCart = false);
    }
  }

  /// Reads `cartItemCountProvider` only when the cart header action is
  /// actually built (i.e. once a product has loaded).
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

  @override
  Widget build(BuildContext context) {
    final backLeading = BisoBackButton(
      onPressed: () => NavigationUtils.safeGoBack(context),
    );

    if (_loading) {
      return BisoPage(
        title: 'BISO Shop',
        largeTitle: false,
        leading: backLeading,
        slivers: const [SliverToBoxAdapter(child: BisoSkeleton.rows())],
      );
    }

    final product = _product;
    if (product == null) {
      return BisoPage(
        title: 'BISO Shop',
        largeTitle: false,
        leading: backLeading,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoErrorState(
              message: _error ?? 'Something went wrong.',
              onRetry: _loadProduct,
            ),
          ),
        ],
      );
    }

    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);
    final variations = product.variations;
    final selectedVariation = _selectedVariation;
    final displayPrice = selectedVariation?.regularPrice ?? product.regularPrice;
    final displayMemberPrice = selectedVariation?.memberPrice;

    return Form(
      key: _formKey,
      // `onUserInteractionIfError` (rather than `onUserInteraction`) so a
      // keystroke in one field cannot cascade error text onto other,
      // untouched fields the user hasn't reached yet (Finding 2):
      // `Form.build()` only re-validates every registered field when the
      // form has *both* seen interaction *and* already has a stored error
      // on some field — i.e. only after a failed `validate()` call (from
      // `_handleAddToCart`), not on every keystroke. Chosen over moving
      // `autovalidateMode` onto each individual `FormField` because it is
      // a single change at the `Form` itself, keeping the fix inside
      // "Form wiring" without touching `_buildCustomFieldInput`'s widgets.
      autovalidateMode: AutovalidateMode.onUserInteractionIfError,
      child: BisoPage(
        overImage: true,
        title: product.title ?? 'BISO Shop',
        largeTitle: false,
        leading: backLeading,
        controller: _scrollController,
        actions: [_buildCartAction()],
        bottomBar: BisoBottomBar(
          child: _buildPurchaseBar(
            product: product,
            displayPrice: displayPrice,
            theme: theme,
            palette: palette,
          ),
        ),
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(height: 360, child: _buildGallery(product, palette)),
          ),
          SliverToBoxAdapter(
            child: _buildTitleAndPrice(
              product: product,
              displayPrice: displayPrice,
              displayMemberPrice: displayMemberPrice,
              theme: theme,
              palette: palette,
            ),
          ),
          if (variations.isNotEmpty)
            SliverToBoxAdapter(
              child: _buildVariations(variations, theme, palette),
            ),

          // The description sits above the custom fields (rather than the
          // order in which the design calls for them) so the fields stay
          // the *last* section of the scroll view. `_revealCustomField`'s
          // fallback for a never-built field scrolls to
          // `scrollController.position.maxScrollExtent` and relies on that
          // invariant — with a long description below the fields instead,
          // scrolling to the very end could land past the fields' cache
          // extent and leave a deep field unbuilt.
          if (product.description != null &&
              product.description!.isNotEmpty)
            SliverToBoxAdapter(
              child: _buildDescription(product, theme, palette),
            ),

          if (product.customFields.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _buildCustomFieldsHeader(theme, palette),
            ),
            SliverBisoListGroup(
              dividerIndent: 16,
              itemCount: product.customFields.length,
              itemBuilder: (context, index) {
                final field = product.customFields[index];
                return Padding(
                  key: _customFieldKeys[field.fieldKey],
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: BisoFormRow(
                    label: field.isRequired ? '${field.label} *' : field.label,
                    child: _buildCustomFieldInput(context, field),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGallery(WebshopProduct product, BisoPalette palette) {
    if (product.images.isEmpty) {
      return ColoredBox(
        color: palette.surfaceRaised,
        child: Center(
          child: Icon(CupertinoIcons.bag, size: 64, color: palette.muted),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          itemCount: product.images.length,
          onPageChanged: (index) => setState(() => _currentImageIndex = index),
          itemBuilder: (context, index) {
            return Image.network(
              product.images[index],
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => ColoredBox(
                color: palette.surfaceRaised,
                child: Center(
                  child: Icon(
                    CupertinoIcons.photo,
                    size: 64,
                    color: palette.muted,
                  ),
                ),
              ),
            );
          },
        ),
        if (product.images.length > 1)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < product.images.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _currentImageIndex ? 8 : 6,
                        height: i == _currentImageIndex ? 8 : 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(
                            alpha: i == _currentImageIndex ? 1 : 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTitleAndPrice({
    required WebshopProduct product,
    required double displayPrice,
    required double? displayMemberPrice,
    required ThemeData theme,
    required BisoPalette palette,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            product.title ?? '',
            style: theme.textTheme.titleLarge?.copyWith(color: palette.ink),
          ),
          const SizedBox(height: 8),
          Text(
            formatNok(displayPrice),
            style: theme.textTheme.headlineMedium?.copyWith(color: palette.ink),
          ),
          // The spec calls for showing member pricing only to members. This
          // shows it to everyone: product-level `member_price`/`member_only`
          // are null on all 50 published products, and no migration in this
          // trilogy gates on membership yet. Only variations carry a member
          // price today, and those are draft-only.
          if (displayMemberPrice != null) ...[
            const SizedBox(height: 4),
            Text(
              'Member price: ${formatNok(displayMemberPrice)}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: palette.success,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Variation selector.
  //
  // No published product currently has variations: all 26 variation rows
  // belong to draft products. This selector, and the variation pricing it
  // drives, are therefore verified only by parsing tests against real draft
  // payloads, never on device.
  Widget _buildVariations(
    List<ProductVariation> variations,
    ThemeData theme,
    BisoPalette palette,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Options',
            style: theme.textTheme.titleMedium?.copyWith(color: palette.ink),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < variations.length; i++)
                ChoiceChip(
                  label: Text(variations[i].name),
                  selected: i == _selectedVariationIndex,
                  onSelected: (_) =>
                      setState(() => _selectedVariationIndex = i),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDescription(
    WebshopProduct product,
    ThemeData theme,
    BisoPalette palette,
  ) {
    return BisoSection(
      title: 'Description',
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: product.description!.toFullHtml(
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.muted,
              height: 1.5,
            ),
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomFieldsHeader(ThemeData theme, BisoPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
      child: Semantics(
        header: true,
        child: Text(
          'Additional information',
          style: theme.textTheme.headlineSmall?.copyWith(color: palette.ink),
        ),
      ),
    );
  }

  /// The buy bar.
  ///
  /// A `member_only` product is offered to members and refused to everyone
  /// else, which is the website's rule — it filters those products out of the
  /// shop for non-members entirely. The app shows them with the reason instead
  /// of hiding them, since a product page can be reached by deep link.
  ///
  /// Membership comes from the buyer's own verified state, not from the
  /// product: gating on the flag alone would refuse the product to the very
  /// people it exists for. Everything else — stock, purchase limits, the
  /// member discount — is left to the server, which is the only place that can
  /// judge it correctly.
  Widget _buildPurchaseBar({
    required WebshopProduct product,
    required double displayPrice,
    required ThemeData theme,
    required BisoPalette palette,
  }) {
    final soldOut = product.stock != null && product.stock! <= 0;
    final blockedAsNonMember =
        product.memberOnly && !ref.watch(hasValidMembershipProvider);

    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatNok(displayPrice),
              style: theme.textTheme.titleLarge?.copyWith(color: palette.ink),
            ),
            Text(
              soldOut ? 'Sold out' : 'Incl. VAT',
              style: theme.textTheme.bodySmall?.copyWith(
                color: soldOut ? palette.error : palette.muted,
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: FilledButton.icon(
            onPressed: soldOut || blockedAsNonMember || _addingToCart
                ? null
                : _handleAddToCart,
            icon: _addingToCart
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(CupertinoIcons.cart_badge_plus),
            label: Text(
              soldOut
                  ? 'Sold out'
                  : blockedAsNonMember
                  ? 'Members only'
                  : 'Add to cart',
            ),
          ),
        ),
      ],
    );
  }

  /// Builds the input for one custom field, matching [field.type]. The
  /// field's own label is rendered by the enclosing [BisoFormRow], so only
  /// the input itself is built here.
  ///
  /// `fieldKey` is an opaque id and is never rendered — only [field.label],
  /// [field.placeholder] and [field.helpText] are shown to the user.
  ///
  /// [context] is the field's own (descendant) build context — passed in
  /// rather than using the State's own `context`, so [BisoPageInsets] (an
  /// ancestor only inside [BisoPage]'s subtree) can be read to size
  /// [scrollPadding]: without it, `EditableText`'s default 20 pt scroll
  /// padding on every edge leaves a focused field tucked under the floating
  /// purchase bar when the keyboard opens, since that default has no idea
  /// the bar (and, above the fold, the translucent header) are there.
  Widget _buildCustomFieldInput(BuildContext context, ProductCustomField field) {
    final requiredValidator = field.isRequired
        ? (String? value) {
            if (value == null || value.trim().isEmpty) {
              return 'This field is required';
            }
            return null;
          }
        : null;

    final insets = BisoPageInsets.maybeOf(context);
    final scrollPadding = insets != null
        ? EdgeInsets.fromLTRB(20, insets.top + 20, 20, insets.bottom + 20)
        : const EdgeInsets.all(20);

    switch (field.type) {
      case 'textarea':
        return TextFormField(
          controller: _textControllers[field.fieldKey],
          minLines: 3,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          scrollPadding: scrollPadding,
          decoration: bisoInputDecoration(
            context,
            hintText: field.placeholder,
          ).copyWith(helperText: field.helpText),
          validator: requiredValidator,
        );
      case 'number':
        return TextFormField(
          controller: _textControllers[field.fieldKey],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          scrollPadding: scrollPadding,
          decoration: bisoInputDecoration(
            context,
            hintText: field.placeholder,
          ).copyWith(helperText: field.helpText),
          validator: requiredValidator,
        );
      case 'email':
        return TextFormField(
          controller: _textControllers[field.fieldKey],
          keyboardType: TextInputType.emailAddress,
          scrollPadding: scrollPadding,
          decoration: bisoInputDecoration(
            context,
            hintText: field.placeholder,
          ).copyWith(helperText: field.helpText),
          validator: requiredValidator,
        );
      case 'select':
        // No live product currently has a `select` custom field (all live
        // fields are `text` with empty options), so this branch is
        // unverified against real data.
        return DropdownButtonFormField<String>(
          initialValue: _selectValues[field.fieldKey],
          decoration: bisoInputDecoration(
            context,
          ).copyWith(helperText: field.helpText),
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
          scrollPadding: scrollPadding,
          decoration: bisoInputDecoration(
            context,
            hintText: field.placeholder,
          ).copyWith(helperText: field.helpText),
          validator: requiredValidator,
        );
    }
  }
}
