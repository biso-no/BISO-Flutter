import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/product_model.dart';
import '../../../data/services/product_service.dart';
import '../../../data/services/chat_service.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../widgets/biso/biso.dart';
import '../chat/chat_conversation_screen.dart';

/// Injectable so tests can replace the Appwrite-backed service with a fake.
/// `_ProductDetailScreenState` watches this instead of constructing
/// `ProductService()` directly.
final productServiceProvider = Provider<ProductService>(
  (ref) => ProductService(),
);

class ProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;

  const ProductDetailScreen({required this.productId, super.key});

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  ProductModel? _product;
  bool _loading = true;
  String? _error;
  bool _isFavorited = false;
  bool _favoriteLoading = false;
  int _currentImageIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadProduct();
  }

  Future<void> _loadProduct() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final service = ref.read(productServiceProvider);
      final product = await service.getProductById(widget.productId);

      if (product == null) {
        setState(() {
          _error = 'Product not found';
          _loading = false;
        });
        return;
      }

      // Check if favorited by current user
      final auth = ref.read(authStateProvider);
      if (auth.isAuthenticated && auth.user != null) {
        final favorited = await service.isFavorited(
          userId: auth.user!.id,
          productId: widget.productId,
        );
        _isFavorited = favorited;
      }

      // Increment view count
      await service.incrementViewCount(widget.productId);

      setState(() {
        _product = product;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load product: $e';
        _loading = false;
      });
    }
  }

  Future<void> _toggleFavorite() async {
    final auth = ref.read(authStateProvider);
    if (!auth.isAuthenticated || auth.user == null) {
      // Show login prompt
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to save favorites')),
        );
      }
      return;
    }

    // Prevent multiple simultaneous calls
    if (_favoriteLoading) return;

    if (mounted) {
      setState(() => _favoriteLoading = true);
    }

    try {
      final service = ref.read(productServiceProvider);
      final newState = await service.toggleFavorite(
        userId: auth.user!.id,
        productId: widget.productId,
      );

      if (mounted) {
        setState(() {
          _isFavorited = newState;
          _favoriteLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newState ? 'Added to favorites' : 'Removed from favorites',
            ),
            duration: const Duration(seconds: 1),
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

  void _contactSeller() async {
    final auth = ref.read(authStateProvider);
    final product = _product;

    if (!auth.isAuthenticated || auth.user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to contact seller')),
      );
      return;
    }

    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product information not available')),
      );
      return;
    }

    if (auth.user!.id == product.sellerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot message yourself')),
      );
      return;
    }

    // Show dialog to compose initial message
    final messageController = TextEditingController(
      text:
          'Hi! I\'m interested in your ${product.name}. Is it still available?',
    );

    final shouldSend = await showDialog<bool>(
      context: context,
      builder: (context) {
        final palette = BisoPalette.of(context);
        return AlertDialog(
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: product.images.isNotEmpty
                      ? Image.network(
                          product.images.first,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return ColoredBox(
                              color: palette.surfaceRaised,
                              child: Icon(
                                CupertinoIcons.bag,
                                color: palette.muted,
                              ),
                            );
                          },
                        )
                      : ColoredBox(
                          color: palette.surfaceRaised,
                          child: Icon(CupertinoIcons.bag, color: palette.muted),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Message ${product.sellerName}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      product.name,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Send a message to ${product.sellerName}:',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: palette.muted),
              ),
              const SizedBox(height: 12),
              BisoFormGroup(
                children: [
                  TextField(
                    controller: messageController,
                    maxLines: 3,
                    decoration: bisoInputDecoration(
                      context,
                      hintText: 'Type your message...',
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Send'),
            ),
          ],
        );
      },
    );

    if (shouldSend == true && messageController.text.trim().isNotEmpty) {
      if (!mounted) return;

      try {
        // Show loading
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: CircularProgressIndicator()),
        );

        final chatService = ChatService();
        final chat = await chatService.createMarketplaceChat(
          buyerId: auth.user!.id,
          buyerName: auth.user!.name,
          sellerId: product.sellerId,
          sellerName: product.sellerName,
          productId: product.id,
          productName: product.name,
          productImageUrl: product.images.isNotEmpty
              ? product.images.first
              : '',
          productPrice: product.price,
          userMessage: messageController.text.trim(),
        );

        if (!mounted) return;

        // Hide loading dialog
        Navigator.of(context).pop();

        // Navigate to chat
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ChatConversationScreen(chat: chat),
          ),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message sent successfully!')),
        );
      } catch (e) {
        if (!mounted) return;

        // Hide loading dialog
        Navigator.of(context).pop();

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
      }
    }

    messageController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backLeading = BisoBackButton(
      onPressed: () =>
          NavigationUtils.safeGoBack(context, fallbackRoute: '/explore/products'),
    );

    if (_loading) {
      return BisoPage(
        title: 'Product Details',
        largeTitle: false,
        leading: backLeading,
        slivers: const [SliverToBoxAdapter(child: BisoSkeleton.rows())],
      );
    }

    if (_error != null) {
      return BisoPage(
        title: 'Product Details',
        largeTitle: false,
        leading: backLeading,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoErrorState(message: _error, onRetry: _loadProduct),
          ),
        ],
      );
    }

    final product = _product!;
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);

    return BisoPage(
      overImage: true,
      title: product.name,
      largeTitle: false,
      leading: backLeading,
      actions: [
        BisoHeaderAction(
          icon: _isFavorited ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
          tooltip: 'Favorite',
          onPressed: _favoriteLoading ? null : _toggleFavorite,
        ),
      ],
      bottomBar: BisoBottomBar(
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _contactSeller,
            icon: const Icon(CupertinoIcons.chat_bubble_text_fill),
            label: const Text('Contact Seller'),
          ),
        ),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 400,
            child: _buildImageGallery(product, palette),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Price and title
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${product.price.toStringAsFixed(0)} ${product.currency}',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: palette.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            product.name,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: palette.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (product.isNegotiable)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: palette.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: palette.warning),
                        ),
                        child: Text(
                          'Negotiable',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: palette.warning,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 16),

                // Category and condition
                Row(
                  children: [
                    if (product.category.isNotEmpty)
                      _buildInfoChip(theme, palette, product.category),
                    if (product.category.isNotEmpty &&
                        product.condition.isNotEmpty)
                      const SizedBox(width: 8),
                    if (product.condition.isNotEmpty)
                      _buildInfoChip(theme, palette, product.condition),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Description
        SliverToBoxAdapter(
          child: BisoSection(
            title: 'Description',
            child: Material(
              color: palette.surface,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  product.description,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.5,
                    color: palette.muted,
                  ),
                ),
              ),
            ),
          ),
        ),

        // Seller info
        SliverToBoxAdapter(child: _buildSellerInfo(product, palette)),
      ],
    );
  }

  Widget _buildInfoChip(ThemeData theme, BisoPalette palette, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(color: palette.muted),
      ),
    );
  }

  Widget _buildImageGallery(ProductModel product, BisoPalette palette) {
    if (product.images.isEmpty) {
      return ColoredBox(
        color: palette.surfaceRaised,
        child: Center(
          child: Icon(CupertinoIcons.photo, size: 64, color: palette.muted),
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
              errorBuilder: (context, error, stackTrace) {
                return ColoredBox(
                  color: palette.surfaceRaised,
                  child: Center(
                    child: Icon(
                      CupertinoIcons.photo,
                      size: 64,
                      color: palette.muted,
                    ),
                  ),
                );
              },
            );
          },
        ),

        // Image page indicator
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

  Widget _buildSellerInfo(ProductModel product, BisoPalette palette) {
    return BisoSection(
      title: 'Seller Information',
      child: BisoListGroup(
        children: [
          BisoListRow(
            title: product.sellerName,
            subtitle: product.contactMethod != null
                ? 'Prefers: ${_contactMethodLabel(product.contactMethod!)}'
                : null,
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: palette.surfaceRaised,
              backgroundImage: product.sellerAvatar != null
                  ? NetworkImage(product.sellerAvatar!)
                  : null,
              child: product.sellerAvatar == null
                  ? Text(
                      product.sellerName.isNotEmpty
                          ? product.sellerName[0].toUpperCase()
                          : 'U',
                      style: TextStyle(
                        color: palette.link,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  String _contactMethodLabel(String method) {
    switch (method) {
      case 'message':
        return 'In-app message';
      case 'phone':
        return 'Phone';
      case 'email':
        return 'Email';
      default:
        return method;
    }
  }
}
