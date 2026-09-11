import '../../../core/theme/biso_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/product_model.dart';
import '../../../data/services/product_service.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/campus/campus_provider.dart';

class SellProductScreen extends ConsumerStatefulWidget {
  const SellProductScreen({super.key});

  @override
  ConsumerState<SellProductScreen> createState() => _SellProductScreenState();
}

class _PremiumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  const _PremiumField({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
  });
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
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
          borderSide: const BorderSide(color: AppColors.defaultBlue),
        ),
      ),
    );
  }
}

class _PremiumPillSelector extends StatelessWidget {
  final String? value;
  final String label;
  final List<String> options;
  final String Function(String) display;
  final bool allowNull;
  final void Function(String) onChanged;
  const _PremiumPillSelector({
    required this.value,
    required this.label,
    required this.options,
    required this.display,
    required this.onChanged,
    this.allowNull = false,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (allowNull)
              _pill(
                context,
                selected: value == null,
                text: 'None',
                onTap: () => onChanged(''),
              ),
            ...options.map(
              (o) => _pill(
                context,
                selected: value == o,
                text: display(o),
                onTap: () => onChanged(o),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _pill(
    BuildContext context, {
    required bool selected,
    required String text,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.subtleBlue : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.defaultBlue : AppColors.outlineVariant,
          ),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? AppColors.defaultBlue : AppColors.charcoalBlack,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
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
    final theme = Theme.of(context);
    final auth = ref.watch(authStateProvider);
    final _ = ref.watch(
      filterCampusProvider,
    ); // keep reactive to campus changes

    if (!auth.isAuthenticated || auth.user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sell Item')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 64,
                  color: AppColors.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  'Please sign in to sell items',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go('/auth/login'),
                  child: const Text('Sign In'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
      appBar: AppBar(
        title: const Text('Sell Item'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _handleCancel,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: _submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Publish'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: BisoNavigationInset.padding(
            context,
            const EdgeInsets.all(16),
          ),
          children: [
            // Images picker
            _buildImagesPicker(theme),

            const SizedBox(height: 16),

            _PremiumField(
              controller: _nameController,
              label: 'Title',
              hint: 'e.g., MacBook Pro 13"',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),

            const SizedBox(height: 12),

            _PremiumField(
              controller: _descriptionController,
              label: 'Description',
              maxLines: 5,
              validator: (v) => (v == null || v.trim().length < 10)
                  ? 'Please add a bit more detail'
                  : null,
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _PremiumField(
                    controller: _priceController,
                    label: 'Price (NOK)',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
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
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _PremiumPillSelector(
                    value: _category,
                    label: 'Category',
                    options: _categories,
                    display: _categoryLabel,
                    onChanged: (v) => setState(() => _category = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PremiumPillSelector(
                    value: _condition,
                    label: 'Condition',
                    options: _conditions,
                    display: _conditionLabel,
                    onChanged: (v) => setState(() => _condition = v),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _isNegotiable,
              onChanged: (v) => setState(() => _isNegotiable = v),
              title: const Text('Price is negotiable'),
            ),

            const Divider(height: 24),

            _PremiumPillSelector(
              value: _contactMethod,
              label: 'Preferred contact (optional)',
              options: _contactMethods,
              display: _contactLabel,
              onChanged: (v) => setState(() => _contactMethod = v),
              allowNull: true,
            ),

            const SizedBox(height: 12),

            _PremiumField(
              controller: _contactInfoController,
              label: 'Contact info (optional)',
            ),

            const SizedBox(height: 32),

            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: const Icon(Icons.publish),
              label: const Text('Publish'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagesPicker(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Photos', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._images.map(
              (x) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(x.path),
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: InkWell(
                      onTap: () => setState(() => _images.remove(x)),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: _pickImages,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.gray50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: const Center(child: Icon(Icons.add_a_photo)),
              ),
            ),
          ],
        ),
      ],
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
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Discard'),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

      final service = ProductService();
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
