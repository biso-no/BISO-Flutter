import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/constants/app_colors.dart';
import '../../../providers/campus/campus_provider.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/services/validator_service.dart';
import '../../../data/models/validation_result_model.dart';

class ControllerModeScreen extends ConsumerStatefulWidget {
  const ControllerModeScreen({super.key});

  @override
  ConsumerState<ControllerModeScreen> createState() =>
      _ControllerModeScreenState();
}

class _ControllerModeScreenState extends ConsumerState<ControllerModeScreen>
    with TickerProviderStateMixin {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  MobileScannerController? controller;
  bool _isFlashOn = false;
  bool _isProcessing = false;
  ValidationResultModel? _lastResult;
  String? _lastError;
  DateTime? _lastScanTime;

  // Animation controllers
  late AnimationController _scanLineController;
  late AnimationController _resultController;
  late AnimationController _pulseController;

  // Animations
  late Animation<double> _scanLineAnimation;
  late Animation<double> _resultAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    controller = MobileScannerController();
  }

  @override
  void dispose() {
    controller?.dispose();
    _scanLineController.dispose();
    _resultController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _initializeAnimations() {
    _scanLineController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _scanLineAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _scanLineController, curve: Curves.easeInOut),
    );

    _resultController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _resultAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _resultController, curve: Curves.elasticOut),
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _scanLineController.repeat(reverse: true);
  }

  @override
  Widget build(BuildContext context) {
    final selectedCampus = ref.watch(selectedCampusProvider);
    final campusColor = _getCampusColor(selectedCampus.id);

    return Scaffold(
      backgroundColor: AppColors.charcoalBlack,
      appBar: AppBar(
        title: const Text(
          'Validator Mode',
          style: TextStyle(color: AppColors.white),
        ),
        backgroundColor: AppColors.charcoalBlack,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.white),
          onPressed: () => NavigationUtils.safeGoBack(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isFlashOn ? Icons.flash_on : Icons.flash_off,
              color: AppColors.white,
            ),
            onPressed: _toggleFlash,
          ),
        ],
      ),
      body: Column(
        children: [
          // Header instructions
          Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.qr_code_scanner, color: campusColor, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Scan Student QR Code',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Point camera at student\'s QR code to verify membership',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.white.withValues(alpha: 0.7)),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // QR Scanner View
          Expanded(
            child: Stack(
              children: [
                // Camera view
                MobileScanner(
                  key: qrKey,
                  controller: controller,
                  onDetect: _onQRDetected,
                ),

                // Custom overlay
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ScannerOverlayPainter(
                      borderColor: campusColor,
                      cutOutSize: 280,
                    ),
                  ),
                ),

                // Animated scan line
                if (!_isProcessing)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _scanLineAnimation,
                      builder: (context, child) {
                        return CustomPaint(
                          painter: _ScanLinePainter(
                            progress: _scanLineAnimation.value,
                            color: campusColor,
                          ),
                        );
                      },
                    ),
                  ),

                // Processing overlay
                if (_isProcessing)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.54),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: campusColor),
                              const SizedBox(height: 16),
                              Text(
                                'Verifying membership...',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Result overlay
                if (_lastResult != null || _lastError != null)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _resultAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _resultAnimation.value,
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.87),
                            child: Center(child: _buildResultCard(campusColor)),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Bottom status panel
          Container(
            padding: const EdgeInsets.all(24),
            color: AppColors.smokeGray,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status: ${_isProcessing ? 'Scanning...' : 'Ready'}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_lastScanTime != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Last scan: ${_formatTime(_lastScanTime!)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.white.withValues(alpha: 0.7)),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_lastResult != null || _lastError != null)
                  FilledButton(
                    onPressed: _clearResult,
                    style: FilledButton.styleFrom(
                      backgroundColor: campusColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(Color campusColor) {
    final isValid = _lastResult?.result == 'VALID';
    final backgroundColor = isValid ? AppColors.green9 : AppColors.error;
    const iconColor = AppColors.white;
    final icon = isValid ? Icons.check_circle : Icons.error;

    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: backgroundColor.withValues(alpha: 0.3),
            offset: const Offset(0, 8),
            blurRadius: 24,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Icon(icon, size: 80, color: iconColor),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            isValid ? 'VALID MEMBER' : 'INVALID',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: iconColor,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 16),
          if (_lastResult?.member != null) ...[
            Text(
              _lastResult!.member!.displayName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: iconColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _lastResult!.member!.membershipName,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: iconColor.withValues(alpha: 0.9),
              ),
            ),
            if (_lastResult!.member!.expiresAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Expires: ${_formatDate(_lastResult!.member!.expiresAt!)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: iconColor.withValues(alpha: 0.8),
                ),
              ),
            ],
          ] else if (_lastError != null) ...[
            Text(
              _lastError!,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: iconColor),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OutlinedButton(
                onPressed: _clearResult,
                style: OutlinedButton.styleFrom(
                  foregroundColor: iconColor,
                  side: BorderSide(color: iconColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('Continue Scanning'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _onQRDetected(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    if (!_isProcessing &&
        barcodes.isNotEmpty &&
        barcodes.first.rawValue != null) {
      _processQRCode(barcodes.first.rawValue!);
    }
  }

  Future<void> _processQRCode(String qrData) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _lastResult = null;
      _lastError = null;
      _lastScanTime = DateTime.now();
    });

    // Haptic feedback
    HapticFeedback.lightImpact();

    try {
      // Extract token from QR data
      String? token = _extractTokenFromQR(qrData);
      if (token == null) {
        throw Exception('Invalid QR code format');
      }

      // Call verification service
      final validatorService = ValidatorService();
      final result = await validatorService.verifyPassToken(
        token: token,
        context: {
          'deviceId': 'flutter_controller',
          'locationHint': 'mobile_validator',
        },
      );

      setState(() {
        _lastResult = result;
        _isProcessing = false;
      });

      // Show result animation
      _resultController.reset();
      _resultController.forward();

      // Pulse animation for result
      _pulseController.repeat(reverse: true);

      // Haptic feedback based on result
      if (result.result == 'VALID') {
        HapticFeedback.selectionClick();
        await Future.delayed(const Duration(milliseconds: 100));
        HapticFeedback.selectionClick();
      } else {
        HapticFeedback.vibrate();
      }
    } catch (e) {
      setState(() {
        _lastError = e.toString();
        _isProcessing = false;
      });

      _resultController.reset();
      _resultController.forward();
      _pulseController.repeat(reverse: true);

      // Error haptic feedback
      HapticFeedback.vibrate();
    }
  }

  String? _extractTokenFromQR(String qrData) {
    // Handle both app link and direct token formats
    if (qrData.startsWith('biso://verify?token=')) {
      return qrData.substring('biso://verify?token='.length);
    } else if (qrData.startsWith('https://app.biso.no/verify?token=')) {
      return qrData.substring('https://app.biso.no/verify?token='.length);
    } else if (qrData.contains('token=')) {
      final uri = Uri.tryParse(qrData);
      return uri?.queryParameters['token'];
    }

    // Assume direct token if no URL format detected
    return qrData.trim();
  }

  void _toggleFlash() async {
    if (controller != null) {
      await controller!.toggleTorch();
      setState(() {
        _isFlashOn = !_isFlashOn;
      });
    }
  }

  void _clearResult() {
    setState(() {
      _lastResult = null;
      _lastError = null;
    });
    _resultController.reset();
    _pulseController.reset();
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

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return isoDate;
    }
  }
}

class _ScanLinePainter extends CustomPainter {
  final double progress;
  final Color color;

  _ScanLinePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Calculate scan area (matching the QR overlay)
    final scanSize = 280.0;
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final scanLeft = centerX - scanSize / 2;
    final scanTop = centerY - scanSize / 2;

    // Draw animated scan line
    final lineY = scanTop + (scanSize * progress);
    canvas.drawLine(
      Offset(scanLeft, lineY),
      Offset(scanLeft + scanSize, lineY),
      paint,
    );

    // Add gradient effect
    final gradient = LinearGradient(
      colors: [
        Colors.transparent,
        color.withValues(alpha: 0.6),
        color.withValues(alpha: 0.8),
        color.withValues(alpha: 0.6),
        Colors.transparent,
      ],
      stops: [0.0, 0.2, 0.5, 0.8, 1.0],
    );

    final gradientPaint = Paint()
      ..shader = gradient.createShader(
        Rect.fromLTWH(scanLeft, lineY - 20, scanSize, 40),
      );

    canvas.drawRect(
      Rect.fromLTWH(scanLeft, lineY - 20, scanSize, 40),
      gradientPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is! _ScanLinePainter ||
        oldDelegate.progress != progress ||
        oldDelegate.color != color;
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final Color borderColor;
  final double cutOutSize;

  _ScannerOverlayPainter({required this.borderColor, required this.cutOutSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.charcoalBlack.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;

    // Calculate center position
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final cutOutLeft = centerX - cutOutSize / 2;
    final cutOutTop = centerY - cutOutSize / 2;

    // Draw overlay with cutout
    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cutOutLeft, cutOutTop, cutOutSize, cutOutSize),
          const Radius.circular(20),
        ),
      )
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(overlayPath, paint);

    // Draw border corners
    final borderPaint = Paint()
      ..color = borderColor
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLength = 40.0;

    // Top-left corner
    canvas.drawLine(
      Offset(cutOutLeft, cutOutTop + cornerLength),
      Offset(cutOutLeft, cutOutTop),
      borderPaint,
    );
    canvas.drawLine(
      Offset(cutOutLeft, cutOutTop),
      Offset(cutOutLeft + cornerLength, cutOutTop),
      borderPaint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(cutOutLeft + cutOutSize - cornerLength, cutOutTop),
      Offset(cutOutLeft + cutOutSize, cutOutTop),
      borderPaint,
    );
    canvas.drawLine(
      Offset(cutOutLeft + cutOutSize, cutOutTop),
      Offset(cutOutLeft + cutOutSize, cutOutTop + cornerLength),
      borderPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(cutOutLeft, cutOutTop + cutOutSize - cornerLength),
      Offset(cutOutLeft, cutOutTop + cutOutSize),
      borderPaint,
    );
    canvas.drawLine(
      Offset(cutOutLeft, cutOutTop + cutOutSize),
      Offset(cutOutLeft + cornerLength, cutOutTop + cutOutSize),
      borderPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(cutOutLeft + cutOutSize - cornerLength, cutOutTop + cutOutSize),
      Offset(cutOutLeft + cutOutSize, cutOutTop + cutOutSize),
      borderPaint,
    );
    canvas.drawLine(
      Offset(cutOutLeft + cutOutSize, cutOutTop + cutOutSize - cornerLength),
      Offset(cutOutLeft + cutOutSize, cutOutTop + cutOutSize),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is! _ScannerOverlayPainter ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.cutOutSize != cutOutSize;
  }
}
