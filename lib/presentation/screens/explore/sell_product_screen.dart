import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/models/product_model.dart';
import '../../../data/services/product_service.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../widgets/biso/biso.dart';

/// Injectable so tests can replace the Appwrite-backed service with a fake.
/// `_SellProductScreenState` watches this instead of constructing
/// `ProductService()` directly.
final _productServiceProvider = Provider<ProductService>(
  (ref) => ProductService(),
);

class SellProductScreen extends ConsumerStatefulWidget {
  const SellProductScreen({super.key});

  @override
  ConsumerState<SellProductScreen> createState() => _SellProductScreenState();
}

class _SellProductScreenState extends ConsumerState<SellProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _contactInfoController = TextEditingController();

  final List<XFile> _images = [];
  bool _submitting = false;

  final String _currency = 'NOK';
  String _category = 'books';
  String _condition = 'good';
  bool _isNegotiable = false;
  String? _contactMethod; // 'message' | 'phone' | 'email'

  final _categories = const [
    'books',
    'electronics',
    'furniture',
    'clothes',
    'sports',
    'other',
  ];
  final _conditions = const ['new', 'like_new', 'good', 'fair', 'poor'];
  final _contactMethods = const ['message', 'phone', 'email'];

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _contactInfoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final _ = ref.watch(
      filterCampusProvider,
    ); // keep reactive to campus changes

    if (!auth.isAuthenticated || auth.user == null) {
      return BisoPage(
        title: 'Sell Item',
        largeTitle: false,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoEmptyState(
              icon: CupertinoIcons.lock,
              accent: BisoAccent.gold,
              title: 'Please sign in to sell items',
              action: FilledButton(
                onPressed: () => context.go('/auth/login'),
                child: const Text('Sign In'),
              ),
            ),
          ),
        ],
      );
    }

    return Form(key: _formKey, child: _buildForm());
  }

  Widget _buildForm() {
    return BisoPage(
      title: 'Sell Item',
      largeTitle: false,
      automaticallyImplyLeading: false,
      actions: [
        BisoHeaderAction(
          icon: CupertinoIcons.xmark,
          tooltip: 'Cancel',
          onPressed: _handleCancel,
        ),
        BisoHeaderAction(
          icon: CupertinoIcons.checkmark,
          tooltip: 'Publish',
          onPressed: _submitting ? null : _submit,
        ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: BisoSection(title: 'Photos', child: _buildImagesPicker()),
        ),
        SliverToBoxAdapter(
          child: Builder(builder: (context) => _buildDetailsGroup(context)),
        ),
        SliverToBoxAdapter(
          child: Builder(builder: (context) => _buildPriceGroup(context)),
        ),
        SliverToBoxAdapter(
          child: BisoFormGroup(
            title: 'Category & condition',
            children: [
              BisoListRow(
                title: 'Category',
                value: _categoryLabel(_category),
                onTap: _showCategoryPicker,
              ),
              BisoListRow(
                title: 'Condition',
                value: _conditionLabel(_condition),
                onTap: _showConditionPicker,
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Builder(builder: (context) => _buildContactGroup(context)),
        ),
      ],
    );
  }

  /// [context] must be a descendant of the enclosing [BisoPage] (obtained via
  /// a [Builder] at each call site) — this state's own context sits above
  /// it, so [BisoPageInsets.maybeOf] would find nothing there and a focused
  /// field could end up tucked behind the translucent header once the
  /// keyboard opens.
  EdgeInsets _scrollPaddingFor(BuildContext context) {
    final insets = BisoPageInsets.maybeOf(context);
    return insets != null
        ? EdgeInsets.fromLTRB(20, insets.top + 20, 20, insets.bottom + 20)
        : const EdgeInsets.all(20);
  }

  Widget _buildDetailsGroup(BuildContext context) {
    final scrollPadding = _scrollPaddingFor(context);
    return BisoFormGroup(
      title: 'Details',
      children: [
        BisoFormRow(
          label: 'Title',
          child: TextFormField(
            controller: _nameController,
            textInputAction: TextInputAction.next,
            scrollPadding: scrollPadding,
            decoration: bisoInputDecoration(
              context,
              hintText: 'e.g., MacBook Pro 13"',
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Title is required' : null,
          ),
        ),
        BisoFormRow(
          label: 'Description',
          child: TextFormField(
            controller: _descriptionController,
            maxLines: 5,
            scrollPadding: scrollPadding,
            decoration: bisoInputDecoration(context),
            validator: (v) => (v == null || v.trim().length < 10)
                ? 'Please add a bit more detail'
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildPriceGroup(BuildContext context) {
    final scrollPadding = _scrollPaddingFor(context);
    return BisoFormGroup(
      title: 'Price',
      children: [
        BisoFormRow(
          label: 'Price (NOK)',
          child: TextFormField(
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            scrollPadding: scrollPadding,
            decoration: bisoInputDecoration(context, prefixText: 'NOK '),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              final num? val = num.tryParse(v.replaceAll(',', '.'));
              if (val == null || val <= 0) {
                return 'Enter a valid amount';
              }
              return null;
            },
          ),
        ),
        BisoListRow(
          title: 'Price is negotiable',
          trailing: Switch.adaptive(
            value: _isNegotiable,
            onChanged: (v) => setState(() => _isNegotiable = v),
          ),
          onTap: () => setState(() => _isNegotiable = !_isNegotiable),
        ),
      ],
    );
  }

  Widget _buildContactGroup(BuildContext context) {
    final scrollPadding = _scrollPaddingFor(context);
    final hasContactMethod =
        _contactMethod != null && _contactMethod!.isNotEmpty;
    return BisoFormGroup(
      title: 'Contact',
      children: [
        BisoListRow(
          title: 'Preferred contact (optional)',
          value: hasContactMethod ? _contactLabel(_contactMethod!) : 'None',
          onTap: _showContactMethodPicker,
        ),
        BisoFormRow(
          label: 'Contact info (optional)',
          child: TextFormField(
            controller: _contactInfoController,
            scrollPadding: scrollPadding,
            decoration: bisoInputDecoration(context),
          ),
        ),
      ],
    );
  }

  Widget _buildImagesPicker() {
    const crossAxisCount = 3;
    const spacing = 8.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final palette = BisoPalette.of(context);
        final tileSize =
            (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
            crossAxisCount;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            ..._images.map(
              (x) => SizedBox(
                width: tileSize,
                height: tileSize,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(
                        File(x.path),
                        width: tileSize,
                        height: tileSize,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GestureDetector(
                        onTap: () => setState(() => _images.remove(x)),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            CupertinoIcons.xmark,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: tileSize,
              height: tileSize,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _pickImages,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.surfaceRaised,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(CupertinoIcons.camera, color: palette.muted),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final result = await picker.pickMultiImage(imageQuality: 85);
    if (result.isNotEmpty) {
      setState(() {
        _images.addAll(result);
        if (_images.length > 6) {
          _images.removeRange(6, _images.length);
        }
      });
    }
  }

  void _showCategoryPicker() {
    _showOptionPicker(
      title: 'Category',
      options: _categories,
      display: _categoryLabel,
      selected: _category,
      onSelected: (v) => setState(() => _category = v),
    );
  }

  void _showConditionPicker() {
    _showOptionPicker(
      title: 'Condition',
      options: _conditions,
      display: _conditionLabel,
      selected: _condition,
      onSelected: (v) => setState(() => _condition = v),
    );
  }

  void _showContactMethodPicker() {
    _showOptionPicker(
      title: 'Preferred contact',
      options: _contactMethods,
      display: _contactLabel,
      // A previous "None" tap stores '' (see below) rather than null — kept
      // exactly so `_hasChanges()`/`_submit()` see the same value as before;
      // both null and '' read as "no selection" here for display only.
      selected: (_contactMethod?.isEmpty ?? true) ? null : _contactMethod,
      allowNull: true,
      onSelected: (v) => setState(() => _contactMethod = v),
    );
  }

  /// One bottom sheet used for category, condition and contact method: a
  /// grouped list of options with a checkmark on the current selection,
  /// mirroring the language sheet in `explore_screen.dart`.
  void _showOptionPicker({
    required String title,
    required List<String> options,
    required String Function(String) display,
    required String? selected,
    required ValueChanged<String> onSelected,
    bool allowNull = false,
  }) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final palette = BisoPalette.of(sheetContext);
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: BisoSection(
              title: title,
              padding: EdgeInsets.zero,
              child: BisoListGroup(
                children: [
                  if (allowNull)
                    BisoListRow(
                      title: 'None',
                      trailing: selected == null
                          ? Icon(CupertinoIcons.checkmark, color: palette.link)
                          : null,
                      onTap: () {
                        // The original pill selector's "None" also passed an
                        // empty string, not null, to its onChanged callback —
                        // kept identical here.
                        onSelected('');
                        Navigator.pop(sheetContext);
                      },
                    ),
                  for (final option in options)
                    BisoListRow(
                      title: display(option),
                      trailing: selected == option
                          ? Icon(CupertinoIcons.checkmark, color: palette.link)
                          : null,
                      onTap: () {
                        onSelected(option);
                        Navigator.pop(sheetContext);
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _hasChanges() {
    return _images.isNotEmpty ||
        _nameController.text.trim().isNotEmpty ||
        _descriptionController.text.trim().isNotEmpty ||
        _priceController.text.trim().isNotEmpty ||
        _contactInfoController.text.trim().isNotEmpty ||
        _contactMethod != null ||
        _isNegotiable ||
        _category != 'books' ||
        _condition != 'good';
  }

  Future<void> _handleCancel() async {
    if (!_hasChanges()) {
      context.go('/explore/products');
      return;
    }
    final discard = await _showDiscardDialog();
    if (!mounted || !discard) return;
    context.go('/explore/products');
  }

  Future<bool> _showDiscardDialog() async {
    final palette = BisoPalette.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'If you leave now, your changes will not be saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: palette.error),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one photo')),
      );
      return;
    }

    final auth = ref.read(authStateProvider);
    final campus = ref.read(filterCampusProvider);
    final user = auth.user!;

    setState(() => _submitting = true);

    try {
      final price = double.parse(_priceController.text.replaceAll(',', '.'));
      final product = ProductModel(
        id: '',
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        price: price,
        currency: _currency,
        sellerId: user.id,
        sellerName: user.name,
        sellerAvatar: user.avatarUrl,
        campusId: campus.id,
        category: _category,
        images: const [],
        condition: _condition,
        status: 'available',
        isNegotiable: _isNegotiable,
        contactMethod: _contactMethod,
        contactInfo: _contactInfoController.text.trim().isEmpty
            ? null
            : _contactInfoController.text.trim(),
      );

      final service = ref.read(_productServiceProvider);
      final createdProduct = await service.createProduct(
        product: product,
        imagePaths: _images.map((x) => x.path).toList(),
      );

      if (!mounted) return;

      // Show success message
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Your item is now live!')));

      // Navigate directly to the new product details screen
      context.go('/explore/products/${createdProduct.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to publish: $e')));
    }
  }

  String _categoryLabel(String c) {
    switch (c) {
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
      default:
        return 'Other';
    }
  }

  String _conditionLabel(String c) {
    switch (c) {
      case 'new':
        return 'Brand new';
      case 'like_new':
        return 'Like new';
      case 'good':
        return 'Good';
      case 'fair':
        return 'Fair';
      case 'poor':
        return 'Poor';
      default:
        return c;
    }
  }

  String _contactLabel(String m) {
    switch (m) {
      case 'message':
        return 'In-app message';
      case 'phone':
        return 'Phone';
      case 'email':
        return 'Email';
      default:
        return m;
    }
  }
}
