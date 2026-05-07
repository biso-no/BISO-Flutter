import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/membership_model.dart';

class MembershipPurchaseModal extends StatefulWidget {
  final String studentId;
  final Color campusColor;
  final List<MembershipPurchaseOption> membershipOptions;
  final Function(
    MembershipPurchaseOption option,
    String paymentMethod,
    String? phoneNumber,
  )
  onPurchase;

  const MembershipPurchaseModal({
    super.key,
    required this.studentId,
    required this.campusColor,
    required this.membershipOptions,
    required this.onPurchase,
  });

  @override
  State<MembershipPurchaseModal> createState() =>
      _MembershipPurchaseModalState();
}

class _MembershipPurchaseModalState extends State<MembershipPurchaseModal>
    with TickerProviderStateMixin {
  MembershipPurchaseOption? selectedOption;
  String selectedPaymentMethod = 'VIPPS'; // 'VIPPS' or 'CARD'
  String? phoneNumber;
  bool isProcessing = false;
  final _phoneController = TextEditingController();

  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return GestureDetector(
      onTap: () => _closeModal(context),
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: 0.5),
        body: GestureDetector(
          onTap: () {}, // Prevent closing when tapping on modal content
          child: Center(
            child: SlideTransition(
              position: _slideAnimation,
              child: Container(
                margin: const EdgeInsets.all(20),
                constraints: BoxConstraints(
                  maxHeight: screenHeight * 0.85,
                  maxWidth: 500,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(theme),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        child: Column(
                          children: [
                            if (widget.membershipOptions.isEmpty) ...[
                              _buildNoMembershipsAvailable(theme),
                            ] else ...[
                              _buildMembershipOptions(theme),
                              const SizedBox(height: 24),
                              if (selectedOption != null) ...[
                                _buildPaymentMethodSelection(theme),
                                const SizedBox(height: 24),
                                if (selectedPaymentMethod == 'VIPPS') ...[
                                  _buildPhoneNumberInput(theme),
                                  const SizedBox(height: 24),
                                ],
                                _buildPurchaseButton(theme),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoMembershipsAvailable(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.gray50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: widget.campusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.info_outline,
              color: widget.campusColor,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No memberships available',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.strongBlue,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'There are currently no active membership plans for your campus. This may be because membership sales are temporarily disabled or undergoing maintenance. Please check back later.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _closeModal(context),
              style: FilledButton.styleFrom(
                backgroundColor: widget.campusColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            widget.campusColor,
            widget.campusColor.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.card_membership,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BISO Membership',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose your membership plan',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _closeModal(context),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildMembershipOptions(ThemeData theme) {
    return Column(
      children: widget.membershipOptions.map((option) {
        final isSelected = selectedOption?.membershipId == option.membershipId;
        final isPopular =
            option.priceNok ==
            widget.membershipOptions
                    .map((o) => o.priceNok)
                    .reduce((a, b) => a > b ? a : b) ~/
                2; // Roughly middle option

        return GestureDetector(
          onTap: () {
            setState(() {
              selectedOption = option;
            });
            HapticFeedback.lightImpact();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? widget.campusColor : AppColors.gray300,
                width: isSelected ? 2 : 1,
              ),
              color: isSelected
                  ? widget.campusColor.withValues(alpha: 0.05)
                  : theme.colorScheme.surface,
            ),
            child: Stack(
              children: [
                // Popular badge
                if (isPopular)
                  Positioned(
                    top: -1,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.defaultGold,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'POPULAR',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.strongBlue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  option.displayName,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? widget.campusColor
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  option.description,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${option.priceNok} NOK',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: widget.campusColor,
                                ),
                              ),
                              if (option.priceNok >
                                  1000) // Assuming expensive memberships are "special"
                                Text(
                                  '~450 NOK/year',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.green9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: option.benefits.map((benefit) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? widget.campusColor.withValues(alpha: 0.1)
                                  : AppColors.gray100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check,
                                  size: 14,
                                  color: isSelected
                                      ? widget.campusColor
                                      : AppColors.green9,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  benefit,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPaymentMethodSelection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment Method',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.strongBlue,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildPaymentMethodCard(
                theme,
                'VIPPS',
                'Vipps/MobilePay',
                Icons.phone_android,
                'Pay with your phone',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildPaymentMethodCard(
                theme,
                'CARD',
                'Card Payment',
                Icons.credit_card,
                'Pay with credit/debit card',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentMethodCard(
    ThemeData theme,
    String method,
    String title,
    IconData icon,
    String subtitle,
  ) {
    final isSelected = selectedPaymentMethod == method;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedPaymentMethod = method;
        });
        HapticFeedback.lightImpact();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? widget.campusColor : AppColors.gray300,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? widget.campusColor.withValues(alpha: 0.05)
              : theme.colorScheme.surface,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected
                  ? widget.campusColor
                  : AppColors.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: isSelected ? widget.campusColor : null,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneNumberInput(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Phone Number (Optional)',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.strongBlue,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _phoneController,
          decoration: const InputDecoration(
            hintText: '+47 xxx xx xxx',
            prefixIcon: Icon(Icons.phone),
            helperText: 'For faster Vipps processing',
          ),
          keyboardType: TextInputType.phone,
          onChanged: (value) {
            phoneNumber = value.trim().isEmpty ? null : value.trim();
          },
        ),
      ],
    );
  }

  Widget _buildPurchaseButton(ThemeData theme) {
    return Column(
      children: [
        // Summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.gray50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Selected Plan', style: theme.textTheme.bodyMedium),
                  Text(
                    selectedOption!.displayName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Payment Method', style: theme.textTheme.bodyMedium),
                  Text(
                    selectedPaymentMethod == 'VIPPS'
                        ? 'Vipps/MobilePay'
                        : 'Card Payment',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${selectedOption!.priceNok} NOK',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: widget.campusColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Purchase button following Vipps guidelines
        SizedBox(
          width: double.infinity,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 56,
            child: FilledButton(
              onPressed: isProcessing ? null : _handlePurchase,
              style: FilledButton.styleFrom(
                backgroundColor: selectedPaymentMethod == 'VIPPS'
                    ? AppColors.vippsPurple
                    : widget.campusColor,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: isProcessing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (selectedPaymentMethod == 'VIPPS')
                          const Text(
                            'Pay with ',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (selectedPaymentMethod == 'VIPPS')
                          const Text(
                            'Vipps',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else
                          Row(
                            children: [
                              const Icon(Icons.credit_card, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Pay ${selectedOption!.priceNok} NOK',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        Text(
          'Secure payment powered by Vipps MobilePay',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  void _handlePurchase() async {
    if (selectedOption == null) return;

    setState(() {
      isProcessing = true;
    });

    try {
      // Add a small delay to show loading state
      await Future.delayed(const Duration(milliseconds: 500));

      widget.onPurchase(selectedOption!, selectedPaymentMethod, phoneNumber);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        isProcessing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Purchase failed: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _closeModal(BuildContext context) async {
    final navigator = Navigator.of(context);
    await _slideController.reverse();
    if (mounted) {
      navigator.pop();
    }
  }
}
