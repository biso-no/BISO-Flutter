import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/navigation_utils.dart';
import '../../../core/utils/norwegian_bank_account.dart';
import '../../../data/models/user_model.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../widgets/biso/biso.dart';

class PaymentInformationScreen extends ConsumerStatefulWidget {
  const PaymentInformationScreen({super.key});

  @override
  ConsumerState<PaymentInformationScreen> createState() =>
      _PaymentInformationScreenState();
}

class _PaymentInformationScreenState
    extends ConsumerState<PaymentInformationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bankAccountController = TextEditingController();
  final _swiftController = TextEditingController();

  bool _isInternational = false;
  bool _isLoading = false;
  bool _didPrefillFromUser = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentData();
  }

  void _loadCurrentData() {
    final user = ref.read(authStateProvider).user;
    if (user != null) {
      _applyUser(user);
      _didPrefillFromUser = true;
    }
  }

  @override
  void dispose() {
    _bankAccountController.dispose();
    _swiftController.dispose();
    super.dispose();
  }

  String? _validateSwift(String? value) {
    if (_isInternational && (value == null || value.isEmpty)) {
      return 'SWIFT code is required for international accounts';
    }

    if (value != null && value.isNotEmpty) {
      // SWIFT code validation (8 or 11 characters)
      if (value.length != 8 && value.length != 11) {
        return 'SWIFT code must be 8 or 11 characters';
      }

      // Basic format validation (letters and numbers only)
      if (!RegExp(r'^[A-Z0-9]+$').hasMatch(value.toUpperCase())) {
        return 'SWIFT code can only contain letters and numbers';
      }
    }

    return null;
  }

  Future<void> _savePaymentInformation() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final bankAccount = _isInternational
          ? _bankAccountController.text.trim()
          : normalizeNorwegianBankAccount(_bankAccountController.text);
      final swift = _isInternational ? _swiftController.text.trim() : null;

      await ref
          .read(authStateProvider.notifier)
          .updatePaymentInformation(bankAccount: bankAccount, swift: swift);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment information saved successfully'),
          ),
        );
        NavigationUtils.safeGoBack(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save payment information: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Prefill when auth state updates and user becomes available
    ref.listen(authStateProvider, (previous, next) {
      final user = next.user;
      if (!_didPrefillFromUser && user != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _applyUser(user);
            _didPrefillFromUser = true;
          }
        });
      }
    });

    return Form(
      key: _formKey,
      child: BisoPage(
        title: 'Payment Information',
        largeTitle: false,
        slivers: [
          SliverToBoxAdapter(
            child: Builder(builder: (context) => _buildInfoBanner(context)),
          ),
          SliverToBoxAdapter(
            child: BisoFormGroup(
              title: 'Account Type',
              children: [
                BisoListRow(
                  leading: BisoIconTile(
                    icon: _isInternational
                        ? CupertinoIcons.globe
                        : CupertinoIcons.flag,
                    accent: BisoAccent.coral,
                  ),
                  title: _isInternational
                      ? 'International Bank Account'
                      : 'Norwegian Bank Account',
                  subtitle: _isInternational
                      ? 'Requires SWIFT code for international transfers'
                      : 'Standard Norwegian bank account with MOD11 validation',
                  trailing: Switch.adaptive(
                    value: _isInternational,
                    onChanged: _setInternational,
                  ),
                  onTap: () => _setInternational(!_isInternational),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Builder(
              builder: (context) => _buildBankAccountGroup(context),
            ),
          ),
          if (_isInternational)
            SliverToBoxAdapter(
              child: Builder(builder: (context) => _buildSwiftGroup(context)),
            ),
          SliverToBoxAdapter(child: _buildSaveButton()),
          SliverToBoxAdapter(
            child: Builder(builder: (context) => _buildSecurityNotice(context)),
          ),
        ],
      ),
    );
  }

  void _setInternational(bool value) {
    setState(() {
      _isInternational = value;
      if (!value) {
        // Clear SWIFT when switching to Norwegian
        _swiftController.clear();
      }
    });
  }

  /// [context] must be a descendant of the enclosing [BisoPage] (obtained via
  /// a [Builder] at each call site) so a focused field's keyboard clearance
  /// accounts for the translucent header, mirroring `sell_product_screen.dart`.
  EdgeInsets _scrollPaddingFor(BuildContext context) {
    final insets = BisoPageInsets.maybeOf(context);
    return insets != null
        ? EdgeInsets.fromLTRB(20, insets.top + 20, 20, insets.bottom + 20)
        : const EdgeInsets.all(20);
  }

  Widget _buildInfoBanner(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.link.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(CupertinoIcons.info_circle, color: palette.link),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Add your bank account information to receive expense reimbursements from BISO.',
                style: text.bodyMedium?.copyWith(color: palette.link),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBankAccountGroup(BuildContext context) {
    final scrollPadding = _scrollPaddingFor(context);
    return BisoFormGroup(
      title: 'Bank Account Number',
      children: [
        BisoFormRow(
          label: _isInternational
              ? 'International Account Number'
              : 'Norwegian Account Number',
          child: TextFormField(
            controller: _bankAccountController,
            scrollPadding: scrollPadding,
            decoration: bisoInputDecoration(
              context,
              hintText: _isInternational
                  ? 'Enter your international account number'
                  : '1234 56 78901',
              prefixIcon: const Icon(CupertinoIcons.building_2_fill),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: _isInternational
                ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z]'))]
                : [
                    FilteringTextInputFormatter.digitsOnly,
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      // Auto-format Norwegian bank account (XXXX XX XXXXX)
                      String text = normalizeNorwegianBankAccount(
                        newValue.text,
                      );
                      if (text.length > 11) text = text.substring(0, 11);
                      var formatted = '';
                      for (int i = 0; i < text.length; i++) {
                        if (i == 4 || i == 6) {
                          formatted += ' ';
                        }
                        formatted += text[i];
                      }

                      return TextEditingValue(
                        text: formatted,
                        selection: TextSelection.collapsed(
                          offset: formatted.length,
                        ),
                      );
                    }),
                  ],
            validator: _isInternational
                ? (value) {
                    if (value == null || value.isEmpty) {
                      return 'Account number is required';
                    }
                    return null;
                  }
                : validateNorwegianBankAccount,
          ),
        ),
      ],
    );
  }

  Widget _buildSwiftGroup(BuildContext context) {
    final scrollPadding = _scrollPaddingFor(context);
    return BisoFormGroup(
      title: 'SWIFT Code',
      children: [
        BisoFormRow(
          label: 'SWIFT/BIC Code',
          child: TextFormField(
            controller: _swiftController,
            scrollPadding: scrollPadding,
            decoration: bisoInputDecoration(
              context,
              hintText: 'DEUTDEFF',
              prefixIcon: const Icon(
                CupertinoIcons.chevron_left_slash_chevron_right,
              ),
            ),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              TextInputFormatter.withFunction((oldValue, newValue) {
                return TextEditingValue(
                  text: newValue.text.toUpperCase(),
                  selection: newValue.selection,
                );
              }),
            ],
            validator: _validateSwift,
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _isLoading ? null : _savePaymentInformation,
          child: _isLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save Payment Information'),
        ),
      ),
    );
  }

  Widget _buildSecurityNotice(BuildContext context) {
    final palette = BisoPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(CupertinoIcons.lock_shield_fill, color: palette.success),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Secure Storage',
                    style: text.titleSmall?.copyWith(color: palette.success),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your payment information is encrypted and stored securely. Only BISO administrators can access this information for reimbursement processing.',
                    style: text.bodySmall?.copyWith(color: palette.success),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _applyUser(UserModel user) {
    if (_bankAccountController.text.isEmpty) {
      _bankAccountController.text = user.bankAccount ?? '';
    }
    if (_swiftController.text.isEmpty) {
      _swiftController.text = user.swift ?? '';
    }
    setState(() {
      _isInternational = user.swift?.isNotEmpty == true;
    });
  }
}
