import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/utils/oslo_time.dart';
import '../../../data/models/member_pass.dart';
import '../../../generated/l10n/app_localizations.dart';
import '../../../providers/member_pass/member_pass_session.dart';
import 'pass_colors.dart';

/// The live member pass, built to match the web pass.
class PassCard extends StatelessWidget {
  const PassCard({
    super.key,
    required this.view,
    this.onTap,
    this.presentation = false,
  });

  final MemberPassView view;
  final VoidCallback? onTap;

  /// Full-screen mode: a larger QR and no "tap to present" hint.
  final bool presentation;

  @override
  Widget build(BuildContext context) {
    final pass = view.pass!;
    final holder = pass.holder;
    final l10n = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final term = holder.term?.label(
      spring: l10n.memberPassSeasonSpring,
      fall: l10n.memberPassSeasonFall,
    );
    final expiry = holder.expiryDate;
    final seconds = (view.msUntilNextSlot / 1000).ceil();

    return Semantics(
      button: onTap != null,
      label: l10n.memberPassTitle,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: ColoredBox(
            color: PassColors.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const HolographicBand(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.memberPassMemberLabel,
                              style: text.displaySmall?.copyWith(
                                color: PassColors.cardInk,
                                fontWeight: FontWeight.w300,
                                letterSpacing: 2,
                              ),
                            ),
                            if (term != null)
                              Text(
                                term,
                                style: text.titleMedium?.copyWith(
                                  color: PassColors.cardMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      LiveClock(serverTime: view.serverTime),
                    ],
                  ),
                ),
                DayStripe(dayColor: pass.dayColor),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final qrSize = math.min(
                        constraints.maxWidth - 24,
                        presentation ? 340.0 : 260.0,
                      );
                      return Column(
                        children: [
                          Center(
                            child: PassQr(code: view.code, size: qrSize),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CountdownRing(
                                progress: view.msUntilNextSlot / passSlotMs,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  l10n.memberPassNextCodeIn(seconds),
                                  style: text.bodySmall?.copyWith(
                                    color: PassColors.cardMuted,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (view.offline) ...[
                                const SizedBox(width: 8),
                                _OfflineChip(label: l10n.memberPassOffline),
                              ],
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        holder.name,
                        style: text.titleLarge?.copyWith(
                          color: PassColors.cardInk,
                        ),
                      ),
                      Text(
                        holder.membershipName,
                        style: text.bodyMedium?.copyWith(
                          color: PassColors.cardMuted,
                        ),
                      ),
                      if (expiry != null)
                        Text(
                          l10n.memberPassValidUntil(
                            DateFormat.yMMMd(locale).format(expiry),
                          ),
                          style: text.bodyMedium?.copyWith(
                            color: PassColors.cardMuted,
                          ),
                        ),
                      if (!presentation && onTap != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          l10n.memberPassTapToPresent,
                          style: text.bodySmall?.copyWith(
                            color: PassColors.cardMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OfflineChip extends StatelessWidget {
  const _OfflineChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: PassColors.cardMuted),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.wifi_slash,
              size: 12,
              color: PassColors.cardInk,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: PassColors.cardInk),
            ),
          ],
        ),
      ),
    );
  }
}

/// A moving holographic band. It never stops: under reduced motion it moves
/// slower, so a screenshot is still told apart from a live pass.
class HolographicBand extends StatefulWidget {
  const HolographicBand({super.key, this.height = 10});

  final double height;

  @override
  State<HolographicBand> createState() => HolographicBandState();
}

@visibleForTesting
class HolographicBandState extends State<HolographicBand>
    with SingleTickerProviderStateMixin {
  static const loop = Duration(seconds: 6);
  static const reducedLoop = Duration(seconds: 24);

  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: loop,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final duration = MediaQuery.disableAnimationsOf(context)
        ? reducedLoop
        : loop;
    if (controller.duration != duration || !controller.isAnimating) {
      controller
        ..duration = duration
        ..repeat();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: CustomPaint(painter: _BandPainter(controller)),
    );
  }
}

class _BandPainter extends CustomPainter {
  _BandPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final dx = animation.value * size.width;
    final colors = PassColors.holographic;
    final stops = [
      for (var i = 0; i < colors.length; i++) i / (colors.length - 1),
    ];
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(dx, 0),
        Offset(dx + size.width, 0),
        colors,
        stops,
        TileMode.repeated,
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_BandPainter oldDelegate) =>
      oldDelegate.animation != animation;
}

/// HH:MM:SS in Oslo, by the server's clock, with a pulsing live dot.
class LiveClock extends StatelessWidget {
  const LiveClock({super.key, this.serverTime});

  final DateTime? serverTime;

  @override
  Widget build(BuildContext context) {
    final time = serverTime;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _LiveDot(),
        const SizedBox(width: 6),
        Text(
          time == null ? '--:--:--' : formatOsloClock(time),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: PassColors.cardInk,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    lowerBound: 0.35,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final duration = MediaQuery.disableAnimationsOf(context)
        ? const Duration(seconds: 3)
        : const Duration(milliseconds: 1200);
    if (_controller.duration != duration) {
      _controller
        ..duration = duration
        ..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: const DecoratedBox(
        decoration: BoxDecoration(
          color: PassColors.liveDot,
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(dimension: 8),
      ),
    );
  }
}

/// Today's color, named, across the full width.
class DayStripe extends StatelessWidget {
  const DayStripe({super.key, required this.dayColor});

  final DayColor dayColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = dayColor.color;
    return ColoredBox(
      color: color,
      child: SizedBox(
        height: 44,
        child: Center(
          child: Text(
            dayColorName(l10n, dayColor.name).toUpperCase(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: PassColors.inkOn(color),
              letterSpacing: 3,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// The QR of the raw code on a white quiet zone. The code is never put in
/// semantics, so screen readers do not read it out.
class PassQr extends StatelessWidget {
  const PassQr({super.key, required this.code, required this.size});

  final String? code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final code = this.code;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PassColors.qrBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox.square(
          dimension: size,
          child: code == null
              ? Center(
                  child: Text(AppLocalizations.of(context)!.memberPassUpdating),
                )
              : ExcludeSemantics(
                  child: QrImageView(
                    data: code,
                    size: size,
                    padding: EdgeInsets.zero,
                    backgroundColor: PassColors.qrBackground,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
        ),
      ),
    );
  }
}

/// How much of the current code's 30 seconds is left.
class CountdownRing extends StatelessWidget {
  const CountdownRing({super.key, required this.progress, this.size = 22});

  final double progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _RingPainter(progress.clamp(0.0, 1.0))),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    final track = Paint()
      ..color = PassColors.cardMuted.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final arc = Paint()
      ..color = PassColors.cardInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawOval(rect, track);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
