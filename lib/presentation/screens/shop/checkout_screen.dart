import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/currency.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/checkout_quote.dart';
import '../../../data/models/payment_provider.dart';
import '../../../data/services/shop_api_client.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/shop/cart_provider.dart';
import '../../../providers/shop/checkout_provider.dart';
import '../../widgets/biso/biso.dart';

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
    final palette = BisoPalette.of(context);
    final auth = ref.watch(authStateProvider);
    final cart = ref.watch(cartProvider);

    // Runs after the frame, never during it — writing to a controller inside
    // build would notify its field mid-build.
    ref.listen(authStateProvider.select((state) => state.user), (_, _) {
      _prefillFromProfile();
    });

    final leading = BisoBackButton(
      onPressed: () => NavigationUtils.safeGoBack(
        context,
        fallbackRoute: '/explore/products/cart',
      ),
    );

    if (!auth.isAuthenticated) {
      return BisoPage(
        title: 'Checkout',
        leading: leading,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoEmptyState(
              icon: CupertinoIcons.lock,
              accent: BisoAccent.coral,
              title: 'Sign in to complete your purchase',
              message:
                  'Your order, your receipt and any member discount are '
                  'tied to your BISO account.',
              action: FilledButton(
                onPressed: () => context.push('/auth/login'),
                child: const Text('Sign in'),
              ),
            ),
          ),
        ],
      );
    }

    if (cart.isEmpty) {
      return BisoPage(
        title: 'Checkout',
        leading: leading,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoEmptyState(
              icon: CupertinoIcons.bag,
              accent: BisoAccent.gold,
              title: 'Your cart is empty',
              message: 'Add something from the shop to check out.',
              action: FilledButton(
                onPressed: () => context.go('/explore/products'),
                child: const Text('Browse the shop'),
              ),
            ),
          ),
        ],
      );
    }

    final quote = ref.watch(checkoutQuoteProvider);

    return quote.when(
      loading: () => BisoPage(
        title: 'Checkout',
        largeTitle: false,
        leading: leading,
        slivers: const [SliverToBoxAdapter(child: BisoSkeleton.rows(count: 3))],
      ),
      error: (error, _) => BisoPage(
        title: 'Checkout',
        largeTitle: false,
        leading: leading,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: BisoEmptyState(
              icon: CupertinoIcons.exclamationmark_triangle,
              title: 'We could not price your cart',
              message: error is ShopApiException
                  ? error.message
                  : 'Something went wrong. Please try again.',
              action: FilledButton(
                onPressed: () => ref.invalidate(checkoutQuoteProvider),
                child: const Text('Try again'),
              ),
            ),
          ),
        ],
      ),
      data: (data) => _buildForm(data, leading, theme, palette),
    );
  }

  Widget _buildForm(
    CheckoutQuote quote,
    Widget leading,
    ThemeData theme,
    BisoPalette palette,
  ) {
    final providers = ref.watch(availablePaymentProvidersProvider);
    final available = providers.valueOrNull ?? const <PaymentProvider>[];

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteractionIfError,
      child: BisoPage(
        title: 'Checkout',
        leading: leading,
        slivers: [
          SliverToBoxAdapter(
            child: Builder(builder: (context) => _buildContactGroup(context)),
          ),
          SliverToBoxAdapter(
            child: RadioGroup<PaymentProvider>(
              groupValue: _resolveSelection(available),
              onChanged: (provider) {
                if (provider != null) {
                  setState(() => _selectedProvider = provider);
                }
              },
              child: BisoFormGroup(
                title: 'How would you like to pay?',
                children: _paymentRows(providers),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: BisoFormGroup(
              title: 'Order summary',
              children: _summaryRows(quote, theme, palette),
            ),
          ),
          if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _ErrorBanner(message: _error!),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: _buildPayButton(quote, available),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'You will be taken to your payment provider to complete the '
                'purchase, then brought back here.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// [context] is a descendant of the enclosing [BisoPage], obtained via a
  /// [Builder] — this state's own context sits above it, so
  /// [BisoPageInsets.maybeOf] would find nothing there. Without the real
  /// insets, `EditableText`'s default scroll padding has no idea the
  /// translucent header (and, on other screens, a floating bottom bar) is
  /// there, and a focused field can end up tucked behind it once the
  /// keyboard opens.
  Widget _buildContactGroup(BuildContext context) {
    final insets = BisoPageInsets.maybeOf(context);
    final scrollPadding = insets != null
        ? EdgeInsets.fromLTRB(20, insets.top + 20, 20, insets.bottom + 20)
        : const EdgeInsets.all(20);

    return BisoFormGroup(
      title: 'Your details',
      children: [
        BisoFormRow(
          label: 'Full name',
          child: TextFormField(
            controller: _nameController,
            textInputAction: TextInputAction.next,
            scrollPadding: scrollPadding,
            decoration: bisoInputDecoration(context),
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'We need a name for the order'
                : null,
          ),
        ),
        BisoFormRow(
          label: 'Email',
          child: TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            scrollPadding: scrollPadding,
            decoration: bisoInputDecoration(
              context,
            ).copyWith(helperText: 'Your receipt goes here'),
            validator: _validateEmail,
          ),
        ),
        BisoFormRow(
          label: 'Phone (optional)',
          child: TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            scrollPadding: scrollPadding,
            decoration: bisoInputDecoration(context),
          ),
        ),
      ],
    );
  }

  List<Widget> _paymentRows(AsyncValue<List<PaymentProvider>> providers) {
    return providers.when(
      loading: () => const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
      error: (_, _) => [
        _ProviderUnavailable(
          message:
              'We could not reach the payment service. Please try again '
              'in a moment.',
          onRetry: () => ref.invalidate(paymentProvidersProvider),
        ),
      ],
      data: (available) => available.isEmpty
          ? const [
              _ProviderUnavailable(
                message:
                    'Payments are temporarily unavailable. Your cart is '
                    'saved — please try again later.',
              ),
            ]
          : [
              for (final provider in available)
                BisoListRow(
                  title: provider.displayName,
                  subtitle: provider.description,
                  leading: BisoIconTile(
                    icon: provider == PaymentProvider.vipps
                        ? CupertinoIcons.device_phone_portrait
                        : CupertinoIcons.creditcard,
                    accent: BisoAccent.coral,
                  ),
                  trailing: Radio<PaymentProvider>.adaptive(value: provider),
                  onTap: () => setState(() => _selectedProvider = provider),
                ),
            ],
    );
  }

  List<Widget> _summaryRows(
    CheckoutQuote quote,
    ThemeData theme,
    BisoPalette palette,
  ) {
    // A `value:` row renders its amount in a `Flexible` with one line and an
    // ellipsis, and an evenly-split `Flexible`+`FittedBox` trailing shrinks
    // the digits rather than truncating them — but shrinking still draws a
    // large-text-scale Total *smaller* than at 1.0x, defeating the point of
    // large text. R11 (amounts and counts never truncate) means the amount
    // must render at its natural size; `_AmountRow` measures it and either
    // shares the row with the (shrinkable/wrappable) label or, when there
    // is not enough room, stacks the label above the amount — full size
    // either way.
    final titleStyle = theme.textTheme.titleMedium?.copyWith(color: palette.ink);
    final subtitleStyle = theme.textTheme.bodyMedium?.copyWith(
      color: palette.muted,
    );
    final amountStyle = theme.textTheme.bodyLarge?.copyWith(
      color: palette.muted,
    );
    final discountStyle = theme.textTheme.titleMedium?.copyWith(
      color: palette.success,
    );
    final discountAmountStyle = theme.textTheme.bodyLarge?.copyWith(
      color: palette.success,
    );

    final rows = <Widget>[
      for (final line in quote.items)
        _AmountRow(
          title: line.title,
          subtitle: '${line.quantity} × ${formatNok(line.unitPrice)}',
          amount: formatNok(line.lineTotal),
          titleStyle: titleStyle,
          subtitleStyle: subtitleStyle,
          amountStyle: amountStyle,
        ),
    ];

    if (quote.discountTotal > 0) {
      rows.add(
        _AmountRow(
          title: 'Subtotal',
          amount: formatNok(quote.originalTotal),
          titleStyle: titleStyle,
          amountStyle: amountStyle,
        ),
      );
      rows.add(
        _AmountRow(
          title: quote.memberDiscountPercent > 0
              ? 'Member discount '
                    '(${quote.memberDiscountPercent.toStringAsFixed(0)}%)'
              : 'Member discount',
          amount: '-${formatNok(quote.discountTotal)}',
          titleStyle: discountStyle,
          amountStyle: discountAmountStyle,
        ),
      );
    }

    rows.add(
      _AmountRow(
        title: 'Total',
        amount: formatNok(quote.total),
        titleStyle: titleStyle,
        amountStyle: theme.textTheme.headlineMedium?.copyWith(
          color: palette.ink,
        ),
      ),
    );

    if (quote.membershipApplied) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.checkmark_seal_fill,
                size: 16,
                color: palette.success,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Your BISO membership discount has been applied.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return rows;
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
            : const Icon(CupertinoIcons.lock),
        label: Text(
          _isStarting
              ? 'Starting payment…'
              : provider == null
              ? 'Payments unavailable'
              : 'Pay ${formatNok(quote.total)} with ${provider.displayName}',
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

/// One "label — amount" row in the order summary (a line total, Subtotal,
/// Member discount, or Total), sized so the amount is never scaled down,
/// and never silently clipped, at any text scale (R11).
///
/// [amount] is measured (at the current [MediaQuery.textScalerOf]) against
/// the width [LayoutBuilder] reports:
/// 1. If it fits beside the label with the label keeping at least 40% of
///    the row, they share one line: an [Expanded] label (free to wrap)
///    beside the amount at its natural width, on one line.
/// 2. Otherwise the label gets a line to itself and the amount is
///    right-aligned on its own line below, still on one line at natural
///    width — the amount alone almost always fits a whole row to itself.
/// 3. Only if it still doesn't (an extreme value in `headlineMedium`, the
///    Total's much larger style, at a large text scale) does the amount
///    wrap — but never *inside* the currency code or the number, which
///    would misread a payment total (e.g. "NOK 135" / "84.50" split mid
///    digit). Instead it renders the two pieces `formatNok` already
///    separates with one space — the code and the number — as two
///    single-line `Text`s in a `Wrap`, which only ever breaks *between*
///    them. This never triggers for the smaller per-line/Subtotal/discount
///    amounts in practice — it exists because a single unbroken line is
///    not always physically wide enough for every style, and the
///    alternative (silently clipping past the row's edge, or breaking a
///    number in half) is exactly what R11 forbids. A `FittedBox` (the
///    previous approach)
///    cannot promise full size either way: splitting the row evenly
///    between an `Expanded` title and a `Flexible` amount, as
///    `BisoListRow` does, caps every amount at about half the row and
///    shrinks it to fit, drawing a large-text-scale Total *smaller* than
///    at 1.0x.
class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.title,
    this.subtitle,
    required this.amount,
    this.titleStyle,
    this.subtitleStyle,
    this.amountStyle,
  });

  final String title;
  final String? subtitle;
  final String amount;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final TextStyle? amountStyle;

  static const _spacing = 8.0;
  static const _minLabelFraction = 0.4;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 10),
        child: MergeSemantics(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth;
              final painter = TextPainter(
                text: TextSpan(text: amount, style: amountStyle),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 1,
              )..layout();
              final sideBySide =
                  maxWidth.isFinite &&
                  (maxWidth - painter.width - _spacing) >=
                      maxWidth * _minLabelFraction;
              // Side by side, the amount fits by construction (the check
              // above already confirms it fits in ≤60% of the row).
              // Stacked, it almost always fits the whole row to itself; the
              // rare exception is tier 3 above.
              final fitsOneLine =
                  sideBySide || !maxWidth.isFinite || painter.width <= maxWidth;

              // Tier 3: split on `formatNok`'s one space into the currency
              // code and the number, and let only *that* gap wrap — each
              // piece stays single-line, so neither can ever break in the
              // middle of a number.
              final amountText = fitsOneLine
                  ? Text(
                      amount,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      softWrap: false,
                      style: amountStyle,
                    )
                  : Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      children: [
                        for (final piece in amount.split(' '))
                          Text(
                            piece,
                            maxLines: 1,
                            softWrap: false,
                            style: amountStyle,
                          ),
                      ],
                    );

              final label = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    // Side by side, the label absorbs whatever the amount
                    // didn't need and may run to a second line; stacked, it
                    // already has the full row to itself.
                    maxLines: sideBySide ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: subtitleStyle,
                      ),
                    ),
                ],
              );

              if (sideBySide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: label),
                    const SizedBox(width: _spacing),
                    amountText,
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  label,
                  const SizedBox(height: 4),
                  Align(alignment: Alignment.centerRight, child: amountText),
                ],
              );
            },
          ),
        ),
      ),
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
    final palette = BisoPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(color: palette.muted),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(CupertinoIcons.arrow_clockwise),
              label: const Text('Try again'),
            ),
          ],
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
    final palette = BisoPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.exclamationmark_circle, color: palette.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.ink),
            ),
          ),
        ],
      ),
    );
  }
}
