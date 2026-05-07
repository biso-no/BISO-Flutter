import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../providers/auth/auth_provider.dart';

class MagicLinkVerifyScreen extends ConsumerStatefulWidget {
  final String userId;
  final String secret;

  const MagicLinkVerifyScreen({
    super.key,
    required this.userId,
    required this.secret,
  });

  @override
  ConsumerState<MagicLinkVerifyScreen> createState() =>
      _MagicLinkVerifyScreenState();
}

class _MagicLinkVerifyScreenState
    extends ConsumerState<MagicLinkVerifyScreen> {
  bool _isVerifying = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _verifyLink());
  }

  Future<void> _verifyLink() async {
    if (_isVerifying) return;

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authStateProvider.notifier).verifyMagicLink(
            widget.userId,
            widget.secret,
          );

      if (mounted) {
        final authState = ref.read(authStateProvider);
        if (authState.needsOnboarding) {
          context.go('/onboarding');
        } else {
          context.go('/');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isVerifying = false;
        });
      }
    }
  }

  Future<void> _clearSessionAndRetry() async {
    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authStateProvider.notifier).clearSession();
      await Future.delayed(const Duration(milliseconds: 500));
      await _verifyLink();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isVerifying = false;
        });
      }
    }
  }

  void _backToLogin() {
    context.go('/auth/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final titleText = _errorMessage != null
        ? 'Sign In Failed'
        : _isVerifying
            ? 'Signing you in...'
            : 'Welcome back!';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),

              Column(
                children: [
                  Image.asset(
                    isDark ? 'assets/logo-dark.png' : 'assets/logo.png',
                    height: 64,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    titleText,
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  if (_isVerifying && _errorMessage == null)
                    Text(
                      'Please wait while we verify your sign-in link...',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                ],
              ),

              const SizedBox(height: 80),

              if (_isVerifying && _errorMessage == null)
                const Center(child: CircularProgressIndicator()),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.error_outline, color: AppColors.error, size: 24),
                      const SizedBox(height: 8),
                      Text(
                        _getErrorMessage(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                if (_shouldShowClearSession())
                  ElevatedButton.icon(
                    onPressed: _clearSessionAndRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Clear session & try again'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.defaultBlue,
                      foregroundColor: Colors.white,
                    ),
                  ),

                const SizedBox(height: 12),

                OutlinedButton.icon(
                  onPressed: _backToLogin,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to sign in'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.defaultBlue,
                    side: const BorderSide(color: AppColors.defaultBlue),
                  ),
                ),
              ],

              const Spacer(),

              Text(
                'BI Student Organisation',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getErrorMessage() {
    if (_errorMessage == null) return '';

    if (_errorMessage!.contains('expired') ||
        _errorMessage!.contains('invalid')) {
      return 'This sign-in link has expired or is no longer valid. Please request a new one.';
    } else if (_errorMessage!.contains('active session')) {
      return 'You may already be signed in. Try clearing your session and signing in again.';
    } else {
      return 'Something went wrong while signing you in. Please try again.';
    }
  }

  bool _shouldShowClearSession() {
    return _errorMessage != null &&
        (_errorMessage!.contains('active session') ||
            _errorMessage!.contains('User (role: guests) missing scope') ||
            _errorMessage!.contains('Invalid credentials'));
  }
}
