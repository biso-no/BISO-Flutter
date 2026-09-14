import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/premium_theme.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../data/models/validation_result_model.dart';
import '../../../data/services/validator_service.dart';
import '../../widgets/biso/biso.dart';

class ControllerModeScreen extends ConsumerStatefulWidget {
  const ControllerModeScreen({
    super.key,
    this.scannerBuilder,
    this.validatorService,
  });

  /// Builds the camera preview. `MobileScanner` needs a platform camera the
  /// test harness doesn't have, so tests substitute a plain widget here. The
  /// default is supplied by the State (see `_defaultScanner`) because it
  /// needs the State-owned `controller` and `qrKey`, which can't be
  /// referenced from a const constructor default; the default call is
  /// otherwise identical to the screen's original `MobileScanner` call.
  final Widget Function(void Function(BarcodeCapture capture) onDetect)?
  scannerBuilder;

  /// Injectable for tests; defaults to a real [ValidatorService].
  final ValidatorService? validatorService;

  @override
  ConsumerState<ControllerModeScreen> createState() =>
      _ControllerModeScreenState();
}

class _ControllerModeScreenState extends ConsumerState<ControllerModeScreen>
    with TickerProviderStateMixin {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  MobileScannerController? controller;
  late final ValidatorService _validatorService =
      widget.validatorService ?? ValidatorService();
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

  Widget _defaultScanner(void Function(BarcodeCapture capture) onDetect) {
    return MobileScanner(key: qrKey, controller: controller, onDetect: onDetect);
  }

  @override
  Widget build(BuildContext context) {
    // The scanner is always dark, regardless of the app's theme mode.
    return Theme(
      data: PremiumTheme.darkTheme,
      child: BisoPage(
        title: 'Validator Mode',
        largeTitle: false,
        overImage: true,
        leading: BisoBackButton(
          onPressed: () => NavigationUtils.safeGoBack(context),
        ),
        actions: [
          BisoHeaderAction(
            icon: _isFlashOn
                ? CupertinoIcons.bolt_fill
                : CupertinoIcons.bolt_slash_fill,
            tooltip: _isFlashOn ? 'Turn flash off' : 'Turn flash on',
            onPressed: _toggleFlash,
          ),
        ],
        body: Builder(
          builder: (context) {
            final palette = BisoPalette.of(context);
            final theme = Theme.of(context);
            final insets = BisoPageInsets.maybeOf(context);
            final topInset = insets?.top ?? 0;
            final bottomInset = insets?.bottom ?? 0;

            return Stack(
              fit: StackFit.expand,
              children: [
                // Camera view
                (widget.scannerBuilder ?? _defaultScanner)(_onQRDetected),

                // Custom overlay
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ScannerOverlayPainter(
                      borderColor: palette.link,
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
                            color: palette.link,
                          ),
                        );
                      },
                    ),
                  ),

                // Instruction card
                Positioned(
                  top: topInset + 8,
                  left: 16,
                  right: 16,
                  child: _buildInstructionCard(theme, palette),
                ),

                // Processing overlay
                if (_isProcessing)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.54),
                      child: Center(
                        child: Material(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(20),
                          clipBehavior: Clip.antiAlias,
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: palette.link),
                                const SizedBox(height: 16),
                                Text(
                                  'Verifying membership...',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: palette.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Result card
                if (_lastResult != null || _lastError != null)
                  Positioned(
                    bottom: bottomInset + 8,
                    left: 16,
                    right: 16,
                    child: AnimatedBuilder(
                      animation: _resultAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _resultAnimation.value,
                          alignment: Alignment.bottomCenter,
                          child: _buildResultCard(theme, palette),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildInstructionCard(ThemeData theme, BisoPalette palette) {
    return Material(
      key: const Key('controllerModeInstructionCard'),
      color: palette.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BisoIconTile(
              icon: CupertinoIcons.qrcode_viewfinder,
              accent: BisoAccent.blue,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'Scan Student QR Code',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: palette.ink,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Point camera at student\'s QR code to verify membership',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.muted,
              ),
              textAlign: TextAlign.center,
            ),
            if (_lastScanTime != null) ...[
              const SizedBox(height: 8),
              Text(
                'Last scan: ${_formatTime(_lastScanTime!)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.muted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(ThemeData theme, BisoPalette palette) {
    final isValid = _lastResult?.result == 'VALID';
    final backgroundColor = isValid ? palette.success : palette.error;
    const iconColor = Colors.white;
    final icon = isValid
        ? CupertinoIcons.checkmark_circle_fill
        : CupertinoIcons.exclamationmark_circle_fill;

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Icon(icon, size: 56, color: iconColor),
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              isValid ? 'VALID MEMBER' : 'INVALID',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: iconColor,
                letterSpacing: 2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            if (_lastResult?.member != null) ...[
              Text(
                _lastResult!.member!.displayName,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: iconColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                _lastResult!.member!.membershipName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: iconColor.withValues(alpha: 0.9),
                ),
                textAlign: TextAlign.center,
              ),
              if (_lastResult!.member!.expiresAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Expires: ${_formatDate(_lastResult!.member!.expiresAt!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: iconColor.withValues(alpha: 0.8),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ] else if (_lastError != null) ...[
              Text(
                _lastError!,
                style: theme.textTheme.bodyMedium?.copyWith(color: iconColor),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _clearResult,
              style: OutlinedButton.styleFrom(
                foregroundColor: iconColor,
                side: const BorderSide(color: iconColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text('Continue Scanning'),
            ),
          ],
        ),
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
      final result = await _validatorService.verifyPassToken(
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
      ..color = Colors.black.withValues(alpha: 0.7)
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
