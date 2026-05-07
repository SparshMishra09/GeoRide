import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A 2.5D perspective-rendered glowing navigation arrow using CustomPainter.
/// Rotation is driven by [relativeAngleDegrees] — the angle from device heading
/// to the next waypoint, in degrees. 0° = straight ahead.
class DirectionArrowPainter extends CustomPainter {
  final double relativeAngleDegrees;
  final bool isNearTurn;
  final double glowPulse; // 0.6 → 1.0 pulsing value from AnimationController
  final Color baseColor;

  const DirectionArrowPainter({
    required this.relativeAngleDegrees,
    required this.isNearTurn,
    required this.glowPulse,
    this.baseColor = const Color(0xFF00E5FF), // Neon Cyan
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(relativeAngleDegrees * math.pi / 180);
    canvas.translate(-cx, -cy);

    final color = isNearTurn ? const Color(0xFFFF6D00) : baseColor;

    // ── Layer 1: Outermost glow ──────────────────────────────────────────
    for (int i = 5; i >= 1; i--) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: (0.04 + i * 0.04) * glowPulse)
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, (i + 1) * 7.0 * glowPulse);
      canvas.drawPath(_arrowPath(cx, size.height, scale: 1.0 + i * 0.10),
          glowPaint);
    }

    // ── Layer 2: 3D shadow (dark underside offset) ───────────────────────
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    canvas.drawPath(_arrowPath(cx, size.height, offsetY: 7), shadowPaint);

    // ── Layer 3: Main gradient fill ──────────────────────────────────────
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color, color.withValues(alpha: 0.55)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;
    canvas.drawPath(_arrowPath(cx, size.height), fillPaint);

    // ── Layer 4: White outline stroke ───────────────────────────────────
    final strokePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(_arrowPath(cx, size.height), strokePaint);

    // ── Layer 5: Specular highlight (gives a plastic 3D look) ───────────
    final specPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final specPath = Path()
      ..moveTo(cx - 11, size.height * 0.54)
      ..lineTo(cx, size.height * 0.09)
      ..lineTo(cx + 9, size.height * 0.44);
    canvas.drawPath(specPath, specPaint);

    canvas.restore();
  }

  Path _arrowPath(double cx, double height,
      {double scale = 1.0, double offsetY = 0}) {
    final w = 30.0 * scale;
    final h = height * scale;
    return Path()
      ..moveTo(cx, offsetY + h * 0.05) // tip
      ..lineTo(cx + w, offsetY + h * 0.52) // right shoulder
      ..lineTo(cx + w * 0.45, offsetY + h * 0.52) // right notch
      ..lineTo(cx + w * 0.45, offsetY + h * 0.95) // right tail
      ..lineTo(cx - w * 0.45, offsetY + h * 0.95) // left tail
      ..lineTo(cx - w * 0.45, offsetY + h * 0.52) // left notch
      ..lineTo(cx - w, offsetY + h * 0.52) // left shoulder
      ..close();
  }

  @override
  bool shouldRepaint(DirectionArrowPainter old) =>
      old.relativeAngleDegrees != relativeAngleDegrees ||
      old.isNearTurn != isNearTurn ||
      old.glowPulse != glowPulse;
}

/// A fully animated floating 3D direction arrow widget.
/// Wraps [DirectionArrowPainter] with floating + pulse animations.
class DirectionArrowWidget extends StatefulWidget {
  final double relativeAngleDegrees;
  final double distanceToNextMeters;
  final bool isNearTurn;

  const DirectionArrowWidget({
    super.key,
    required this.relativeAngleDegrees,
    required this.distanceToNextMeters,
    required this.isNearTurn,
  });

  @override
  State<DirectionArrowWidget> createState() => _DirectionArrowWidgetState();
}

class _DirectionArrowWidgetState extends State<DirectionArrowWidget>
    with TickerProviderStateMixin {
  late final AnimationController _floatController;
  late final AnimationController _pulseController;
  late final Animation<double> _floatAnim;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    _floatAnim =
        Tween<double>(begin: -10, end: 10).animate(CurvedAnimation(
      parent: _floatController,
      curve: Curves.easeInOut,
    ));

    _pulseAnim =
        Tween<double>(begin: 0.7, end: 1.0).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _floatController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  String _distanceLabel() {
    final d = widget.distanceToNextMeters;
    if (d < 1000) return '${d.toInt()} m';
    return '${(d / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.isNearTurn ? const Color(0xFFFF6D00) : const Color(0xFF00E5FF);

    return AnimatedBuilder(
      animation: Listenable.merge([_floatAnim, _pulseAnim]),
      builder: (ctx, _) {
        return Transform.translate(
          offset: Offset(0, _floatAnim.value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Distance chip
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 10,
                    )
                  ],
                ),
                child: Text(
                  _distanceLabel(),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // The 3D arrow
              Transform.scale(
                scale: widget.isNearTurn ? (0.9 + _pulseAnim.value * 0.2) : 1.0,
                child: CustomPaint(
                  size: const Size(80, 100),
                  painter: DirectionArrowPainter(
                    relativeAngleDegrees: widget.relativeAngleDegrees,
                    isNearTurn: widget.isNearTurn,
                    glowPulse: _pulseAnim.value,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
