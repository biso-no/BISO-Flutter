import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../../data/models/user_model.dart';

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

  String? _validateNorwegianBankAccount(String? value) {
    if (value == null || value.isEmpty) {
      return 'Bank account number is required';
    }

    // Remove spaces and keep only digits
    final cleanValue = value.replaceAll(RegExp(r'[^\d]'), '');

    if (cleanValue.length != 11) {
      return 'Norwegian bank account must be 11 digits';
    }

    // MOD11 validation for Norwegian bank accounts
    if (!_isValidNorwegianBankAccount(cleanValue)) {
      return 'Invalid Norwegian bank account number';
    }

    return null;
  }

  bool _isValidNorwegianBankAccount(String accountNumber) {
    if (accountNumber.length != 11) return false;

    // MOD11 weights for Norwegian bank account validation
    const weights = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];

    int sum = 0;
    for (int i = 0; i < 10; i++) {
      sum += int.parse(accountNumber[i]) * weights[i];
    }

    int remainder = sum % 11;
    int checkDigit = remainder == 0 ? 0 : 11 - remainder;

    // Check digit cannot be 10
    if (checkDigit == 10) return false;

    return checkDigit == int.parse(accountNumber[10]);
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
      final bankAccount = _bankAccountController.text.trim();
      final swift = _isInternational ? _swiftController.text.trim() : null;

      await ref
          .read(authStateProvider.notifier)
          .updatePaymentInformation(bankAccount: bankAccount, swift: swift);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment information saved successfully'),
            backgroundColor: AppColors.defaultBlue,
          ),
        );
        NavigationUtils.safeGoBack(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save payment information: $e'),
            backgroundColor: AppColors.error,
          ),
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
    final theme = Theme.of(context);
    final selectedCampus = ref.watch(selectedCampusProvider);

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Information'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Information Card
              Card(
                color: AppColors.subtleBlue,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: AppColors.defaultBlue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Add your bank account information to receive expense reimbursements from BISO.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.defaultBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Account Type Toggle
              Text(
                'Account Type',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.strongBlue,
                ),
              ),

              const SizedBox(height: 12),

              Card(
                child: SwitchListTile(
                  secondary: Icon(
                    _isInternational ? Icons.public : Icons.flag,
                    color: _isInternational
                        ? AppColors.purple9
                        : AppColors.defaultBlue,
                  ),
                  title: Text(
                    _isInternational
                        ? 'International Bank Account'
                        : 'Norwegian Bank Account',
                  ),
                  subtitle: Text(
                    _isInternational
                        ? 'Requires SWIFT code for international transfers'
                        : 'Standard Norwegian bank account with MOD11 validation',
                  ),
                  value: _isInternational,
                  onChanged: (value) {
                    setState(() {
                      _isInternational = value;
                      if (!value) {
                        // Clear SWIFT when switching to Norwegian
                        _swiftController.clear();
                      }
                    });
                  },
                  activeThumbColor: _getCampusColor(selectedCampus.id),
                ),
              ),

              const SizedBox(height: 24),

              // Bank Account Field
              Text(
                'Bank Account Number',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.strongBlue,
                ),
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _bankAccountController,
                decoration: InputDecoration(
                  labelText: _isInternational
                      ? 'International Account Number'
                      : 'Norwegian Account Number',
                  hintText: _isInternational
                      ? 'Enter your international account number'
                      : '1234 56 78901',
                  prefixIcon: const Icon(Icons.account_balance),
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: _isInternational
                    ? [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9A-Za-z]'),
                        ),
                      ]
                    : [
                        FilteringTextInputFormatter.digitsOnly,
                        TextInputFormatter.withFunction((oldValue, newValue) {
                          // Auto-format Norwegian bank account (XXXX XX XXXXX)
                          String text = newValue.text.replaceAll(
                            RegExp(r'[^\d]'),
                            '',
                          );
                          if (text.length > 11) text = text.substring(0, 11);

                          String formatted = '';
                          for (int i = 0; i < text.length; i++) {
                            if (i == 4 || i == 6) formatted += ' ';
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
                    : _validateNorwegianBankAccount,
              ),

              // SWIFT Code Field (conditional)
              if (_isInternational) ...[
                const SizedBox(height: 24),

                Text(
                  'SWIFT Code',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.strongBlue,
                  ),
                ),

                const SizedBox(height: 12),

                TextFormField(
                  controller: _swiftController,
                  decoration: const InputDecoration(
                    labelText: 'SWIFT/BIC Code',
                    hintText: 'DEUTDEFF',
                    prefixIcon: Icon(Icons.code),
                    border: OutlineInputBorder(),
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
              ],

              const SizedBox(height: 32),

              // Save Button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isLoading ? null : _savePaymentInformation,
                  style: FilledButton.styleFrom(
                    backgroundColor: _getCampusColor(selectedCampus.id),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text('Save Payment Information'),
                ),
              ),

              const SizedBox(height: 24),

              // Security Notice
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.green9.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.security, color: AppColors.green9),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Secure Storage',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.green9,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Your payment information is encrypted and stored securely. Only BISO administrators can access this information for reimbursement processing.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.green9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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

  Color _getCampusColor(String campusId) {
    switch (campusId) {
      case 'oslo':
        return AppColors.defaultBlue;
      case 'bergen':
        return AppColors.green9;
      case 'trondheim':
        return AppColors.purple9;
      case 'stavanger':
        return AppColors.orange9;
      default:
        return AppColors.gray400;
    }
  }
}
