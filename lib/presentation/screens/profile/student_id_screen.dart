import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:async';
import 'dart:math' as math;

import '../../../core/constants/app_colors.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/student_id_model.dart';
import '../../widgets/show_membership_purchase_modal.dart';
import '../../../data/services/validator_service.dart';

class StudentIdScreen extends ConsumerStatefulWidget {
  const StudentIdScreen({super.key});

  @override
  ConsumerState<StudentIdScreen> createState() => _StudentIdScreenState();
}

class _StudentIdScreenState extends ConsumerState<StudentIdScreen>
    with TickerProviderStateMixin {
  Timer? _tokenRefreshTimer;
  Timer? _animationTimer;
  Timer? _countdownUpdateTimer;
  String? _currentToken;
  DateTime? _tokenExpiry;
  DateTime? _serverTime;
  bool _isLoadingToken = false;
  String? _tokenError;
  int _remainingSeconds = 0;

  // Animation controllers
  late AnimationController _watermarkController;
  late AnimationController _pulseController;
  late AnimationController _countdownController;
  late AnimationController _gradientController;

  // Animation values
  late Animation<double> _watermarkAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _countdownAnimation;
  late Animation<double> _gradientAnimation;

  // Services
  late final ValidatorService _validatorService = ValidatorService();

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startTokenRefresh();
  }

  @override
  void dispose() {
    _tokenRefreshTimer?.cancel();
    _animationTimer?.cancel();
    _countdownUpdateTimer?.cancel();
    _watermarkController.dispose();
    _pulseController.dispose();
    _countdownController.dispose();
    _gradientController.dispose();
    super.dispose();
  }

  void _initializeAnimations() {
    // Watermark animation (moves every 10s)
    _watermarkController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    );
    _watermarkAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _watermarkController, curve: Curves.easeInOut),
    );

    // Pulse animation (continuous)
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Countdown animation (30s cycle)
    _countdownController = AnimationController(
      duration: const Duration(seconds: 30),
      vsync: this,
    );
    _countdownAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _countdownController, curve: Curves.linear),
    );

    // Gradient animation (continuous subtle movement)
    _gradientController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    );
    _gradientAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _gradientController, curve: Curves.easeInOut),
    );

    // Start continuous animations
    _pulseController.repeat(reverse: true);
    _gradientController.repeat();
    _countdownController.repeat();
  }

  void _startTokenRefresh() {
    // Initial token fetch
    _fetchNewToken();

    // Set up timer for token refresh every 30 seconds
    _tokenRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _fetchNewToken();
    });

    // Set up timer for watermark animation every 10 seconds
    _animationTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _watermarkController.forward(from: 0);
    });

    // Set up countdown update timer (updates every second)
    _countdownUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateCountdown();
    });
  }

  void _updateCountdown() {
    if (_tokenExpiry != null) {
      final now = DateTime.now();
      final timeUntilExpiry = _tokenExpiry!.difference(now).inSeconds;

      if (mounted) {
        setState(() {
          _remainingSeconds = timeUntilExpiry > 0 ? timeUntilExpiry : 0;
        });
      }
    }
  }

  Future<void> _fetchNewToken() async {
    if (_isLoadingToken) return;

    setState(() {
      _isLoadingToken = true;
      _tokenError = null;
    });

    try {
      final result = await _validatorService.issuePassToken();

      if (result.ok) {
        setState(() {
          _currentToken = result.token;
          _tokenExpiry = DateTime.now().add(
            Duration(seconds: result.ttlSeconds),
          );
          _serverTime = result.serverTime;
          _remainingSeconds = result.ttlSeconds;
          _isLoadingToken = false;
        });

        // Reset countdown animation
        _countdownController.reset();
        _countdownController.forward();
      } else {
        setState(() {
          _tokenError =
              result.error ?? 'Failed to generate verification token.';
          _isLoadingToken = false;
        });
      }
    } catch (e) {
      String userFriendlyError;

      if (e.toString().contains('NO_ACTIVE_MEMBERSHIP')) {
        userFriendlyError =
            'No active membership found. Please purchase a BISO membership first.';
      } else if (e.toString().contains('NO_STUDENT_ID')) {
        userFriendlyError =
            'Student ID not found. Please verify your student status first.';
      } else if (e.toString().contains('UNAUTHENTICATED')) {
        userFriendlyError = 'Authentication required. Please log in again.';
      } else if (e.toString().contains('FAILED_TO_VERIFY_MEMBERSHIP')) {
        userFriendlyError =
            'Unable to verify membership status. Please try again.';
      } else {
        userFriendlyError = 'Network error: ${e.toString()}';
      }

      setState(() {
        _tokenError = userFriendlyError;
        _isLoadingToken = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final studentRecord = authState.studentRecord;
    final hasStudentId = authState.hasStudentId;
    final isStudentVerified = authState.isStudentVerified;
    final hasValidMembership = authState.hasValidMembership;
    final membershipStatus = authState.membershipStatus;
    final selectedCampus = ref.watch(selectedCampusProvider);
    final campusColor = _getCampusColor(selectedCampus.id);

    // Use the continuously updated countdown

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Verification'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => NavigationUtils.safeGoBack(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Premium Header Card with Animation
            _PremiumHeaderCard(
              campusColor: campusColor,
              campusName: selectedCampus.name,
            ),

            const SizedBox(height: 24),

            if (authState.isLoading)
              _LoadingCard(campusColor: campusColor)
            else if (authState.error != null)
              _ErrorCard(
                error: authState.error!,
                onRetry: () =>
                    ref.read(authStateProvider.notifier).refreshProfile(),
                campusColor: campusColor,
              )
            else if (!hasStudentId)
              _RegisterStudentIdSection(
                onOAuthRegistration: () => _registerStudentIdOAuth(),
                campusColor: campusColor,
              )
            else
              _AnimatedStudentIdCard(
                studentRecord: studentRecord!,
                campusName: selectedCampus.name,
                campusColor: campusColor,
                isVerified: isStudentVerified,
                hasValidMembership: hasValidMembership,
                membershipStatus: membershipStatus,
                expiryDate:
                    authState.membershipVerification?.membership?.expiryDate,
                currentToken: _currentToken,
                tokenExpiry: _tokenExpiry,
                serverTime: _serverTime,
                isLoadingToken: _isLoadingToken,
                tokenError: _tokenError,
                remainingSeconds: _remainingSeconds,
                watermarkAnimation: _watermarkAnimation,
                pulseAnimation: _pulseAnimation,
                countdownAnimation: _countdownAnimation,
                gradientAnimation: _gradientAnimation,
                onCheckMembership: () => _checkMembershipStatus(),
                onPurchaseMembership: () => _purchaseMembership(),
                onRemove: () => _removeStudentId(),
                onRefreshToken: () => _fetchNewToken(),
                onCopyToken: () => _copyTokenToClipboard(),
              ),

            const SizedBox(height: 24),

            // Premium Benefits Section
            _PremiumBenefitsSection(
              campusColor: campusColor,
              hasValidMembership: hasValidMembership,
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
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

  void _registerStudentIdOAuth() {
    ref.read(authStateProvider.notifier).registerStudentIdViaOAuth();
  }

  void _checkMembershipStatus() {
    ref.read(authStateProvider.notifier).checkMembershipStatus();
  }

  void _purchaseMembership() {
    final authState = ref.read(authStateProvider);
    final studentNumber = authState.studentNumber;
    final selectedCampus = ref.read(selectedCampusProvider);
    final campusColor = _getCampusColor(selectedCampus.id);

    if (studentNumber == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please register your student ID first.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    showMembershipPurchaseModal(
      context,
      ref,
      studentId: studentNumber,
      campusColor: campusColor,
    );
  }

  void _removeStudentId() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Student ID'),
        content: const Text(
          'Are you sure you want to remove your student ID? This will remove your verified status and access to student benefits.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(authStateProvider.notifier).removeStudentId();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _copyTokenToClipboard() {
    if (_currentToken != null) {
      final qrData = 'biso://verify?token=$_currentToken';
      Clipboard.setData(ClipboardData(text: qrData));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'QR data copied to clipboard: ${qrData.substring(0, 40)}...',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }
}

// Premium UI Components

class _PremiumHeaderCard extends StatelessWidget {
  final Color campusColor;
  final String campusName;

  const _PremiumHeaderCard({
    required this.campusColor,
    required this.campusName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [campusColor, campusColor.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: campusColor.withValues(alpha: 0.3),
            offset: const Offset(0, 8),
            blurRadius: 20,
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.verified_user,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Student Verification',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Verify your BI $campusName student status and unlock exclusive features, membership benefits, and campus-wide access.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  final Color campusColor;

  const _LoadingCard({required this.campusColor});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            CircularProgressIndicator(color: campusColor),
            const SizedBox(height: 16),
            Text(
              'Loading student information...',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  final Color campusColor;

  const _ErrorCard({
    required this.error,
    required this.onRetry,
    required this.campusColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.error_outline,
                color: AppColors.error,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: FilledButton.styleFrom(
                backgroundColor: campusColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegisterStudentIdSection extends StatelessWidget {
  final VoidCallback onOAuthRegistration;
  final Color campusColor;

  const _RegisterStudentIdSection({
    required this.onOAuthRegistration,
    required this.campusColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Verify Your Student Status',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: campusColor,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            Text(
              'Connect with your BI student account for instant verification and access to exclusive member features.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // OAuth Registration Card
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    campusColor.withValues(alpha: 0.15),
                    campusColor.withValues(alpha: 0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: campusColor.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: campusColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.verified_user,
                      color: campusColor,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Sign In with BI Account',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: campusColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Use your @bi.no email for secure, instant verification. This ensures your student ID belongs to you.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.onSurfaceVariant,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onOAuthRegistration,
                    icon: const Icon(Icons.login),
                    label: const Text('Connect BI Account'),
                    style: FilledButton.styleFrom(
                      backgroundColor: campusColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 32,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Security Notice
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.blue1.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.blue6.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.security, color: AppColors.blue9, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Secure Verification',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: AppColors.blue9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your credentials are processed securely through BI\'s official authentication system. We never store your password.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.blue8,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Benefits Preview
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.green1.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.green6.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.star, color: AppColors.green9, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Unlock After Verification',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppColors.green9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Check membership status\n• Purchase BISO membership\n• Access exclusive features\n• Expense reimbursements',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.green8,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedBackgroundPainter extends CustomPainter {
  final Color campusColor;
  final double animationValue;

  _AnimatedBackgroundPainter({
    required this.campusColor,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gradient = LinearGradient(
      colors: [
        campusColor.withValues(alpha: 0.1),
        campusColor.withValues(alpha: 0.05),
        Colors.white,
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: [0.0, 0.7, 1.0],
    );

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.fill;

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is! _AnimatedBackgroundPainter) return true;
    return oldDelegate.campusColor != campusColor ||
        oldDelegate.animationValue != animationValue;
  }
}

class _AnimatedStudentIdCard extends StatelessWidget {
  final StudentIdModel studentRecord;
  final String campusName;
  final Color campusColor;
  final bool isVerified;
  final bool hasValidMembership;
  final String membershipStatus;
  final DateTime? expiryDate;
  final String? currentToken;
  final DateTime? tokenExpiry;
  final DateTime? serverTime;
  final bool isLoadingToken;
  final String? tokenError;
  final int remainingSeconds;
  final Animation<double> watermarkAnimation;
  final Animation<double> pulseAnimation;
  final Animation<double> countdownAnimation;
  final Animation<double> gradientAnimation;
  final VoidCallback onCheckMembership;
  final VoidCallback onPurchaseMembership;
  final VoidCallback onRemove;
  final VoidCallback onRefreshToken;
  final VoidCallback onCopyToken;

  const _AnimatedStudentIdCard({
    required this.studentRecord,
    required this.campusName,
    required this.campusColor,
    required this.isVerified,
    required this.hasValidMembership,
    required this.membershipStatus,
    required this.expiryDate,
    required this.currentToken,
    required this.tokenExpiry,
    required this.serverTime,
    required this.isLoadingToken,
    required this.tokenError,
    required this.remainingSeconds,
    required this.watermarkAnimation,
    required this.pulseAnimation,
    required this.countdownAnimation,
    required this.gradientAnimation,
    required this.onCheckMembership,
    required this.onPurchaseMembership,
    required this.onRemove,
    required this.onRefreshToken,
    required this.onCopyToken,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExpired = remainingSeconds <= 0;
    final isExpiringSoon = remainingSeconds <= 10;

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              campusColor.withValues(alpha: 0.1),
              campusColor.withValues(alpha: 0.05),
              Colors.white,
            ],
            stops: [0.0, 0.7, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Animated background elements
            Positioned.fill(
              child: AnimatedBuilder(
                animation: gradientAnimation,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _AnimatedBackgroundPainter(
                      campusColor: campusColor,
                      animationValue: gradientAnimation.value,
                    ),
                  );
                },
              ),
            ),

            // Floating particles
            Positioned.fill(
              child: AnimatedBuilder(
                animation: gradientAnimation,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _ParticlePainter(
                      campusColor: campusColor,
                      animationValue: gradientAnimation.value,
                    ),
                  );
                },
              ),
            ),

            // Moving watermark
            Positioned(
              top: 20 + (watermarkAnimation.value * 20),
              right: 20 + (watermarkAnimation.value * 15),
              child: AnimatedBuilder(
                animation: watermarkAnimation,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: watermarkAnimation.value * math.pi * 0.1,
                    child: Opacity(
                      opacity: 0.1 + (watermarkAnimation.value * 0.05),
                      child: Icon(
                        Icons.verified_user,
                        size: 40 + (watermarkAnimation.value * 10),
                        color: campusColor,
                      ),
                    ),
                  );
                },
              ),
            ),

            // "Now" glyph that changes every 10 seconds
            Positioned(
              top: 20,
              left: 20,
              child: AnimatedBuilder(
                animation: watermarkAnimation,
                builder: (context, child) {
                  final glyphIndex =
                      ((watermarkAnimation.value * 10).floor() % 3).toInt();
                  final glyph = _getNowGlyph(glyphIndex);

                  return Transform.rotate(
                    angle: watermarkAnimation.value * math.pi * 0.05,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: campusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(glyph, size: 16, color: campusColor),
                    ),
                  );
                },
              ),
            ),

            // Main content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Header with student info
                  Row(
                    children: [
                      // Animated avatar
                      AnimatedBuilder(
                        animation: pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: pulseAnimation.value,
                            child: Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    campusColor,
                                    campusColor.withValues(alpha: 0.8),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: campusColor.withValues(alpha: 0.3),
                                    offset: const Offset(0, 8),
                                    blurRadius: 20,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.school,
                                color: Colors.white,
                                size: 35,
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(width: 20),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              studentRecord.studentNumber,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: campusColor,
                              ),
                            ),
                            Text(
                              'BI $campusName',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: AppColors.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _PremiumStatusBadge(
                              isVerified: isVerified,
                              hasValidMembership: hasValidMembership,
                              membershipStatus: membershipStatus,
                              campusColor: campusColor,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // QR Code Section - Enhanced Design
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white,
                          campusColor.withValues(alpha: 0.02),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: campusColor.withValues(alpha: 0.08),
                          offset: const Offset(0, 8),
                          blurRadius: 32,
                          spreadRadius: 0,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          offset: const Offset(0, 2),
                          blurRadius: 8,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    campusColor.withValues(alpha: 0.1),
                                    campusColor.withValues(alpha: 0.05),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.qr_code_2,
                                color: campusColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Verification Code',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).colorScheme.onSurface,
                                        ),
                                  ),
                                  Text(
                                    'Show this to validators',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Enhanced QR Code with countdown ring
                        GestureDetector(
                          onTap: () => _showQRDialog(context, campusColor),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Smooth countdown ring with gradient
                              SizedBox(
                                width: 180,
                                height: 180,
                                child: AnimatedBuilder(
                                  animation: countdownAnimation,
                                  builder: (context, child) {
                                    return CustomPaint(
                                      painter: _PremiumCountdownRingPainter(
                                        progress: countdownAnimation.value,
                                        color: _getStatusColor(tokenExpiry),
                                        strokeWidth: 6,
                                      ),
                                    );
                                  },
                                ),
                              ),

                              // QR Code container with enhanced styling
                              Container(
                                width: 150,
                                height: 150,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: campusColor.withValues(alpha: 0.1),
                                      offset: const Offset(0, 4),
                                      blurRadius: 20,
                                      spreadRadius: 0,
                                    ),
                                  ],
                                  border: Border.all(
                                    color: campusColor.withValues(alpha: 0.15),
                                    width: 2,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: _buildQRCodeContent(
                                    context,
                                    campusColor,
                                  ),
                                ),
                              ),

                              // Tap indicator
                              if (currentToken != null &&
                                  !isLoadingToken &&
                                  tokenError == null)
                                Positioned(
                                  bottom: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: campusColor,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: campusColor.withValues(
                                            alpha: 0.3,
                                          ),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.fullscreen,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Token info and refresh button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Token expires in',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  '${remainingSeconds}s',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: isExpired
                                        ? AppColors.error
                                        : isExpiringSoon
                                        ? AppColors.orange9
                                        : campusColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            FilledButton.icon(
                              onPressed: onRefreshToken,
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Refresh'),
                              style: FilledButton.styleFrom(
                                backgroundColor: campusColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (currentToken != null)
                              IconButton(
                                onPressed: onCopyToken,
                                icon: const Icon(Icons.copy, size: 18),
                                tooltip: 'Copy token for testing',
                                style: IconButton.styleFrom(
                                  backgroundColor: campusColor.withValues(
                                    alpha: 0.1,
                                  ),
                                  foregroundColor: campusColor,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Action buttons
                  if (isVerified && !hasValidMembership) ...[
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: onPurchaseMembership,
                            icon: const Icon(Icons.shopping_cart),
                            label: const Text('Purchase Membership'),
                            style: FilledButton.styleFrom(
                              backgroundColor: campusColor,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: onCheckMembership,
                          child: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ] else if (isVerified && hasValidMembership) ...[
                    OutlinedButton.icon(
                      onPressed: onCheckMembership,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh Status'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: campusColor,
                        side: BorderSide(color: campusColor),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getNowGlyph(int index) {
    switch (index) {
      case 0:
        return Icons.change_history;
      case 1:
        return Icons.circle;
      case 2:
        return Icons.square;
      default:
        return Icons.change_history;
    }
  }

  Color _getStatusColor(DateTime? tokenExpiry) {
    if (remainingSeconds <= 0) {
      return AppColors.error;
    } else if (remainingSeconds <= 10) {
      return AppColors.orange9;
    } else {
      return campusColor;
    }
  }

  Widget _buildQRCodeContent(BuildContext context, Color campusColor) {
    final theme = Theme.of(context);

    if (isLoadingToken) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: campusColor,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Generating...',
              style: theme.textTheme.bodySmall?.copyWith(
                color: campusColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (tokenError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: AppColors.error, size: 32),
            const SizedBox(height: 8),
            Text(
              'QR Error',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (currentToken != null) {
      return Stack(
        children: [
          _QRCodePlaceholder(
            qrData: 'biso://verify?token=$currentToken',
            campusColor: campusColor,
          ),
          // Enhanced shimmer effect
          if (!(tokenExpiry?.isBefore(DateTime.now()) ?? true))
            Positioned.fill(
              child: AnimatedBuilder(
                animation: gradientAnimation,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _EnhancedShimmerPainter(
                      campusColor: campusColor,
                      animationValue: gradientAnimation.value,
                    ),
                  );
                },
              ),
            ),
        ],
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.qr_code_2,
            color: campusColor.withValues(alpha: 0.6),
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'Tap to Generate',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: campusColor.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showQRDialog(BuildContext context, Color campusColor) {
    if (currentToken == null) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 320,
          height: 420,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 40,
                spreadRadius: 0,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      campusColor.withValues(alpha: 0.1),
                      campusColor.withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.qr_code_2, color: campusColor, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Verification QR Code',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: campusColor,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: campusColor),
                    ),
                  ],
                ),
              ),

              // Large QR Code
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1.0, // Force square aspect ratio
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: campusColor.withValues(alpha: 0.1),
                              blurRadius: 20,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: _QRCodePlaceholder(
                            qrData: 'biso://verify?token=$currentToken',
                            campusColor: campusColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Footer with timer
              Container(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.timer, color: campusColor, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Expires in ${remainingSeconds}s',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: campusColor,
                        fontWeight: FontWeight.w500,
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
}

class _PremiumStatusBadge extends StatelessWidget {
  final bool isVerified;
  final bool hasValidMembership;
  final String membershipStatus;
  final Color campusColor;

  const _PremiumStatusBadge({
    required this.isVerified,
    required this.hasValidMembership,
    required this.membershipStatus,
    required this.campusColor,
  });

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor;
    String text;

    if (hasValidMembership) {
      backgroundColor = AppColors.green9;
      textColor = Colors.white;
      text = 'Member';
    } else if (isVerified) {
      backgroundColor = AppColors.blue9;
      textColor = Colors.white;
      text = 'Verified';
    } else {
      backgroundColor = AppColors.orange9;
      textColor = Colors.white;
      text = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _PremiumBenefitsSection extends StatelessWidget {
  final Color campusColor;
  final bool hasValidMembership;

  const _PremiumBenefitsSection({
    required this.campusColor,
    required this.hasValidMembership,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hasValidMembership ? 'Your Member Benefits' : 'Unlock These Benefits',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: campusColor,
          ),
        ),

        const SizedBox(height: 16),

        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _BenefitItem(
                  icon: Icons.chat,
                  title: 'Exclusive Chat Channels',
                  description: 'Access to member-only discussion groups',
                  campusColor: campusColor,
                  isUnlocked: hasValidMembership,
                ),
                const SizedBox(height: 20),
                _BenefitItem(
                  icon: Icons.receipt_long,
                  title: 'Expense Reimbursement',
                  description: 'Submit and track your expense claims',
                  campusColor: campusColor,
                  isUnlocked: hasValidMembership,
                ),
                const SizedBox(height: 20),
                _BenefitItem(
                  icon: Icons.local_offer,
                  title: 'Member Discounts',
                  description: 'Exclusive deals on marketplace items',
                  campusColor: campusColor,
                  isUnlocked: hasValidMembership,
                ),
                const SizedBox(height: 20),
                _BenefitItem(
                  icon: Icons.event,
                  title: 'Priority Event Access',
                  description: 'Early registration for popular events',
                  campusColor: campusColor,
                  isUnlocked: hasValidMembership,
                ),
                const SizedBox(height: 20),
                _BenefitItem(
                  icon: Icons.workspace_premium,
                  title: 'Premium Features',
                  description: 'Advanced app features and tools',
                  campusColor: campusColor,
                  isUnlocked: hasValidMembership,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BenefitItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color campusColor;
  final bool isUnlocked;

  const _BenefitItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.campusColor,
    required this.isUnlocked,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isUnlocked
                ? campusColor.withValues(alpha: 0.15)
                : AppColors.gray100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: isUnlocked ? campusColor : AppColors.gray400,
            size: 24,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isUnlocked ? null : AppColors.gray600,
                    ),
                  ),
                  if (isUnlocked) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.check_circle, color: AppColors.green9, size: 16),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isUnlocked
                      ? AppColors.onSurfaceVariant
                      : AppColors.gray500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QRCodePlaceholder extends StatelessWidget {
  final String qrData;
  final Color campusColor;

  const _QRCodePlaceholder({required this.qrData, required this.campusColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: QrImageView(
        data: qrData,
        version: QrVersions.auto,
        size: double.infinity,
        backgroundColor: AppColors.white,
        dataModuleStyle: QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: campusColor,
        ),
        eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: campusColor),
        errorCorrectionLevel: QrErrorCorrectLevel.M,
        padding: const EdgeInsets.all(8),
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final Color campusColor;
  final double animationValue;

  _ParticlePainter({required this.campusColor, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Create 8 floating particles
    for (int i = 0; i < 8; i++) {
      final angle = (i / 8.0) * 2 * math.pi + animationValue * 2 * math.pi;
      final radius = 80 + math.sin(animationValue * 4 + i) * 20;
      final x = size.width / 2 + math.cos(angle) * radius;
      final y = size.height / 2 + math.sin(angle) * radius;

      final opacity = 0.1 + 0.05 * math.sin(animationValue * 3 + i);
      final particleSize = 2 + math.sin(animationValue * 2 + i) * 1;

      paint.color = campusColor.withValues(alpha: opacity);
      canvas.drawCircle(Offset(x, y), particleSize, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is! _ParticlePainter ||
        oldDelegate.campusColor != campusColor ||
        oldDelegate.animationValue != animationValue;
  }
}

class _PremiumCountdownRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _PremiumCountdownRingPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - strokeWidth / 2;

    // Background ring with subtle gradient
    final backgroundPaint = Paint()
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [color.withValues(alpha: 0.08), color.withValues(alpha: 0.12)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, backgroundPaint);

    // Progress ring with enhanced gradient
    if (progress > 0) {
      final progressPaint = Paint()
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: 0.8),
            color,
            color.withValues(alpha: 0.9),
          ],
          stops: [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius));

      final sweepAngle = (progress * 360).toDouble();
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -90, // Start from the top
        sweepAngle,
        false,
        progressPaint,
      );
    }

    // Subtle inner glow
    if (progress > 0.1) {
      final glowPaint = Paint()
        ..strokeWidth = strokeWidth * 0.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.3);

      final sweepAngle = (progress * 360).toDouble();
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth * 0.25),
        -90,
        sweepAngle,
        false,
        glowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is! _PremiumCountdownRingPainter ||
        oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class _EnhancedShimmerPainter extends CustomPainter {
  final Color campusColor;
  final double animationValue;

  _EnhancedShimmerPainter({
    required this.campusColor,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Create multiple shimmer waves
    final shimmerWidth = size.width * 0.25;
    final shimmerPosition =
        (animationValue * (size.width + shimmerWidth)) - shimmerWidth;

    // Primary shimmer
    final primaryGradient = LinearGradient(
      colors: [
        Colors.transparent,
        campusColor.withValues(alpha: 0.08),
        campusColor.withValues(alpha: 0.15),
        campusColor.withValues(alpha: 0.08),
        Colors.transparent,
      ],
      stops: [0.0, 0.2, 0.5, 0.8, 1.0],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );

    final primaryRect = Rect.fromLTWH(
      shimmerPosition,
      0,
      shimmerWidth,
      size.height,
    );

    paint.shader = primaryGradient.createShader(primaryRect);
    canvas.drawRect(primaryRect, paint);

    // Secondary shimmer (offset)
    final secondaryShimmerPosition = shimmerPosition - shimmerWidth * 0.7;
    final secondaryGradient = LinearGradient(
      colors: [
        Colors.transparent,
        campusColor.withValues(alpha: 0.04),
        campusColor.withValues(alpha: 0.08),
        campusColor.withValues(alpha: 0.04),
        Colors.transparent,
      ],
      stops: [0.0, 0.3, 0.5, 0.7, 1.0],
    );

    final secondaryRect = Rect.fromLTWH(
      secondaryShimmerPosition,
      0,
      shimmerWidth * 0.6,
      size.height,
    );

    paint.shader = secondaryGradient.createShader(secondaryRect);
    canvas.drawRect(secondaryRect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is! _EnhancedShimmerPainter ||
        oldDelegate.campusColor != campusColor ||
        oldDelegate.animationValue != animationValue;
  }
}
