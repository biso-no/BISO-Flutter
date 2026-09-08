import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/checkout_quote.dart';
import '../../../data/models/payment_provider.dart';
import '../../../data/services/shop_api_client.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/shop/cart_provider.dart';
import '../../../providers/shop/checkout_provider.dart';

/// Where the buyer confirms who they are, how they want to pay, and what it
/// costs — then leaves for Vipps or the card form.
///
/// Two things on this screen come from the server rather than from the app,
/// deliberately:
///
/// * the payment methods, because a provider is offerable only when its kill
///   switch is on *and* its credentials are configured, and the second is not
///   readable from a phone;
/// * the total, because the member discount depends on a membership lookup the
///   app cannot perform. The quote shown here is the same number the checkout
///   endpoint recomputes, so the price displayed is the price charged.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  PaymentProvider? _selectedProvider;
  bool _isStarting = false;
  String? _error;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    // The profile is usually already loaded by the time the buyer reaches
    // checkout; when it is not, the listener in `build` fills the form in as
    // soon as it arrives.
    _prefillFromProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// Fills the form from the signed-in profile, once.
  ///
  /// Only once: after that the fields are the buyer's to edit, and a late
  /// profile refresh must not overwrite what they have typed.
  void _prefillFromProfile() {
    if (_prefilled) return;
    final user = ref.read(authStateProvider).user;
    if (user == null) return;
    _nameController.text = user.name;
    _emailController.text = user.email;
    _phoneController.text = user.phone ?? '';
    _prefilled = true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final auth = ref.watch(authStateProvider);
    final cart = ref.watch(cartProvider);

    // Runs after the frame, never during it — writing to a controller inside
    // build would notify its field mid-build.
    ref.listen(authStateProvider.select((state) => state.user), (_, _) {
      _prefillFromProfile();
    });

    return Scaffold(
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        elevation: 0,
        leading: NavigationUtils.buildBackButton(
          context,
          fallbackRoute: '/explore/products/cart',
        ),
        title: const Text('Checkout'),
        centerTitle: true,
      ),
      body: _buildBody(auth.isAuthenticated, cart.isEmpty, theme),
    );
  }

  Widget _buildBody(bool isAuthenticated, bool cartIsEmpty, ThemeData theme) {
    if (!isAuthenticated) {
      return _SignInPrompt(
        onSignIn: () => context.push('/auth/login'),
      );
    }
    if (cartIsEmpty) {
      return _CheckoutMessage(
        icon: Icons.shopping_bag_outlined,
        title: 'Your cart is empty',
        message: 'Add something from the shop to check out.',
        actionLabel: 'Browse the shop',
        onAction: () => context.go('/explore/products'),
      );
    }

    final quote = ref.watch(checkoutQuoteProvider);

    return quote.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _CheckoutMessage(
        icon: Icons.error_outline_rounded,
        title: 'We could not price your cart',
        message: error is ShopApiException
            ? error.message
            : 'Something went wrong. Please try again.',
        actionLabel: 'Back to cart',
        onAction: () => context.go('/explore/products/cart'),
        secondaryLabel: 'Try again',
        onSecondary: () => ref.invalidate(checkoutQuoteProvider),
      ),
      data: (data) => _buildForm(data, theme),
    );
  }

  Widget _buildForm(CheckoutQuote quote, ThemeData theme) {
    final providers = ref.watch(availablePaymentProvidersProvider);

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteractionIfError,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _SectionCard(
            step: 1,
            title: 'Your details',
            child: Column(
              children: [
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                      ? 'We need a name for the order'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    helperText: 'Your receipt goes here',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateEmail,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            step: 2,
            title: 'How would you like to pay?',
            child: providers.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => _ProviderUnavailable(
                message:
                    'We could not reach the payment service. Please try again '
                    'in a moment.',
                onRetry: () => ref.invalidate(paymentProvidersProvider),
              ),
              data: (available) => available.isEmpty
                  ? const _ProviderUnavailable(
                      message:
                          'Payments are temporarily unavailable. Your cart is '
                          'saved — please try again later.',
                    )
                  : _ProviderPicker(
                      providers: available,
                      selected: _resolveSelection(available),
                      onSelected: (provider) =>
                          setState(() => _selectedProvider = provider),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            step: 3,
            title: 'Order summary',
            child: _OrderSummary(quote: quote),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 24),
          _buildPayButton(quote, providers.valueOrNull ?? const []),
          const SizedBox(height: 12),
          Text(
            'You will be taken to your payment provider to complete the '
            'purchase, then brought back here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Keeps the selection valid: defaults to the first offerable provider, and
  /// drops a selection that has since been switched off.
  PaymentProvider? _resolveSelection(List<PaymentProvider> available) {
    if (available.isEmpty) return null;
    final selected = _selectedProvider;
    if (selected != null && available.contains(selected)) return selected;
    return available.first;
  }

  Widget _buildPayButton(CheckoutQuote quote, List<PaymentProvider> available) {
    final provider = _resolveSelection(available);
    final canPay = provider != null && !_isStarting;

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: canPay ? () => _startPayment(provider, quote) : null,
        icon: _isStarting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.lock_outline_rounded),
        label: Text(
          _isStarting
              ? 'Starting payment…'
              : provider == null
              ? 'Payments unavailable'
              : 'Pay ${formatNok(quote.total)} with ${provider.displayName}',
        ),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: AppColors.defaultBlue,
        ),
      ),
    );
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'We need an email for your receipt';
    if (!email.contains('@') || !email.contains('.')) {
      return 'That does not look like an email address';
    }
    return null;
  }

  Future<void> _startPayment(
    PaymentProvider provider,
    CheckoutQuote quote,
  ) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isStarting = true;
      _error = null;
    });

    final name = _nameController.text.trim();
    final nameParts = name.split(RegExp(r'\s+'));

    try {
      final started = await ref
          .read(checkoutControllerProvider.notifier)
          .start(
            provider: provider,
            subtotal: quote.subtotal,
            // The server recomputes this and refuses the request if it
            // disagrees, so passing the quote's own total is what keeps the
            // displayed price and the charged price the same number.
            total: quote.total,
            email: _emailController.text.trim(),
            firstName: nameParts.first,
            lastName: nameParts.length > 1
                ? nameParts.sublist(1).join(' ')
                : null,
            phone: _phoneController.text.trim(),
          );

      final launched = await launchUrl(
        Uri.parse(started.checkoutUrl),
        // Vipps needs to hand off to its own app, and a card form belongs in a
        // real browser with the buyer's autofill — neither works in an
        // in-app webview.
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        // Reported here rather than on the status screen, so the buyer sees it
        // on the page they are still looking at. The order stays payable: a
        // retry within the idempotency window reuses this same session.
        throw const ShopApiException(
          'We could not open your payment provider.',
        );
      }

      if (!mounted) return;

      // Move to the status screen once the handoff has actually happened, so
      // there is somewhere to come back to whether the buyer finishes,
      // cancels, or just switches away.
      context.go('/explore/products/order/${started.orderId}');
    } on ShopApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
      if (error.isConflict) {
        // Something in the cart is no longer available; the quote will say
        // what when it refreshes.
        ref.invalidate(checkoutQuoteProvider);
      }
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'We could not start the payment. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.step,
    required this.title,
    required this.child,
  });

  final int step;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: AppColors.defaultBlue,
                child: Text(
                  '$step',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ProviderPicker extends StatelessWidget {
  const _ProviderPicker({
    required this.providers,
    required this.selected,
    required this.onSelected,
  });

  final List<PaymentProvider> providers;
  final PaymentProvider? selected;
  final ValueChanged<PaymentProvider> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final provider in providers)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onSelected(provider),
              child: Semantics(
                selected: provider == selected,
                button: true,
                label: '${provider.displayName}. ${provider.description}',
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: provider == selected
                          ? AppColors.defaultBlue
                          : AppColors.gray100,
                      width: provider == selected ? 2 : 1,
                    ),
                    color: provider == selected
                        ? AppColors.subtleBlue.withValues(alpha: 0.35)
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        provider == PaymentProvider.vipps
                            ? Icons.smartphone_rounded
                            : Icons.credit_card_rounded,
                        color: AppColors.defaultBlue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              provider.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              provider.description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        provider == selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: provider == selected
                            ? AppColors.defaultBlue
                            : AppColors.mist,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ProviderUnavailable extends StatelessWidget {
  const _ProviderUnavailable({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ],
    );
  }
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({required this.quote});

  final CheckoutQuote quote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final line in quote.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${line.quantity} × ${formatNok(line.unitPrice)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(formatNok(line.lineTotal)),
              ],
            ),
          ),
        const Divider(),
        if (quote.discountTotal > 0) ...[
          _SummaryRow(
            label: 'Subtotal',
            value: formatNok(quote.originalTotal),
          ),
          _SummaryRow(
            label: quote.memberDiscountPercent > 0
                ? 'Member discount '
                      '(${quote.memberDiscountPercent.toStringAsFixed(0)}%)'
                : 'Member discount',
            value: '-${formatNok(quote.discountTotal)}',
            highlight: true,
          ),
          const SizedBox(height: 4),
        ],
        Row(
          children: [
            Text(
              'Total',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              formatNok(quote.total),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.defaultBlue,
              ),
            ),
          ],
        ),
        if (quote.membershipApplied) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.card_membership_rounded,
                size: 16,
                color: AppColors.strongGold,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Your BISO membership discount has been applied.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: highlight ? AppColors.green9 : AppColors.onSurfaceVariant,
      fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return _CheckoutMessage(
      icon: Icons.lock_outline_rounded,
      title: 'Sign in to complete your purchase',
      message:
          'Your order, your receipt and any member discount are tied to your '
          'BISO account.',
      actionLabel: 'Sign in',
      onAction: onSignIn,
    );
  }
}

class _CheckoutMessage extends StatelessWidget {
  const _CheckoutMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.mist),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.defaultBlue,
              ),
              child: Text(actionLabel),
            ),
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
