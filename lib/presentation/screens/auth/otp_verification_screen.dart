import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../widgets/biso/biso.dart';

import '../../../core/logging/print_migration.dart';

class OtpVerificationScreen extends ConsumerStatefulWidget {
  final String email;

  const OtpVerificationScreen({super.key, required this.email});

  @override
  ConsumerState<OtpVerificationScreen> createState() =>
      _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  final List<TextEditingController> _controllers = List.generate(
    AppConstants.otpLength,
    (index) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    AppConstants.otpLength,
    (index) => FocusNode(),
  );

  bool _isLoading = false;
  bool _isResending = false;
  Timer? _resendTimer;
  int _resendCountdown = 60;
  String _otpCode = '';

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendCountdown = 60;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown <= 0) {
        timer.cancel();
      } else {
        setState(() => _resendCountdown--);
      }
    });
  }

  void _onDigitChanged(int index, String value) {
    if (value.isEmpty) {
      // Handle backspace
      if (index > 0) {
        _focusNodes[index - 1].requestFocus();
      }
      return;
    }

    if (value.length == 1) {
      // Move to next field
      if (index < AppConstants.otpLength - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        // Last digit entered, hide keyboard
        FocusScope.of(context).unfocus();
      }
    }

    // Build complete OTP code
    _otpCode = _controllers.map((c) => c.text).join();

    // Auto-verify when all digits are entered
    if (_otpCode.length == AppConstants.otpLength) {
      _verifyOtp();
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpCode.length != AppConstants.otpLength) return;

    logPrint('🔥 DEBUG: Starting OTP verification with code: $_otpCode');
    setState(() => _isLoading = true);

    try {
      final authState = ref.read(authStateProvider);
      logPrint(
        '🔥 DEBUG: Current auth state - pendingUserId: ${authState.pendingUserId}',
      );

      if (authState.pendingUserId == null) {
        logPrint('🔥 DEBUG: No pending userId found!');
        throw Exception('No pending OTP verification');
      }

      logPrint(
        '🔥 DEBUG: Calling verifyOtp with userId: ${authState.pendingUserId}, code: $_otpCode',
      );
      await ref
          .read(authStateProvider.notifier)
          .verifyOtp(authState.pendingUserId!, _otpCode);

      if (mounted) {
        final updatedAuthState = ref.read(authStateProvider);
        logPrint(
          '🔥 DEBUG: OTP verification completed, user: ${updatedAuthState.user?.email}',
        );

        // Always redirect to home after successful authentication
        logPrint('🔥 DEBUG: Authentication successful, going to home');
        context.go('/home');
      }
    } catch (e) {
      logPrint('🔥 DEBUG: OTP verification error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)?.invalidOtpCodeMessage ?? 'Invalid OTP code'),
            backgroundColor: BisoPalette.of(context).error,
          ),
        );

        // Clear OTP fields
        for (final controller in _controllers) {
          controller.clear();
        }
        _focusNodes[0].requestFocus();
        _otpCode = '';
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resendOtp() async {
    if (_isResending || _resendCountdown > 0) return;

    setState(() => _isResending = true);

    try {
      await ref.read(authStateProvider.notifier).sendOtp(widget.email);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Verification code sent successfully'),
            backgroundColor: BisoPalette.of(context).success,
          ),
        );
        _startResendTimer();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to resend code: $e'),
            backgroundColor: BisoPalette.of(context).error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final palette = BisoPalette.of(context);

    return BisoPage(
      largeTitle: false,
      // The old AppBar's back button always went to /auth/login rather than
      // popping — this screen is only ever reached via context.go, which
      // leaves nothing to pop, so BisoPage's automatic leading would render
      // nothing here. Keep the explicit target instead of losing the button.
      leading: BisoBackButton(onPressed: () => context.go('/auth/login')),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),

                // Title
                Text(
                  l10n.verifyOtp,
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: palette.ink,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 16),

                // Subtitle
                Text(
                  '${l10n.otpSentTo} ${widget.email}',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: palette.muted,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 32),

                // OTP Input Fields
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                    AppConstants.otpLength,
                    (index) => _OtpDigitField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      onChanged: (value) => _onDigitChanged(index, value),
                      isLoading: _isLoading,
                    ),
                  ),
                ),

                const SizedBox(height: 48),

                // Resend Code
                if (_resendCountdown > 0)
                  Text(
                    'Resend code in ${_resendCountdown}s',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.muted,
                    ),
                    textAlign: TextAlign.center,
                  )
                else
                  TextButton(
                    onPressed: _isResending ? null : _resendOtp,
                    child: _isResending
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.resendCode),
                  ),

                const Spacer(),

                // Loading Indicator
                if (_isLoading) const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OtpDigitField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Function(String) onChanged;
  final bool isLoading;

  const _OtpDigitField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final palette = BisoPalette.of(context);

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        border: Border.all(
          color: focusNode.hasFocus ? palette.link : palette.hairline,
          width: focusNode.hasFocus ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: !isLoading,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: palette.ink,
        ),
        keyboardType: TextInputType.number,
        maxLength: 1,
        onChanged: onChanged,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          counterText: '',
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
