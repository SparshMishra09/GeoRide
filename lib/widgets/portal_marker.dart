import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A beautiful glowing portal marker for sharing stops.
/// Features: pulsing outer ring, orbiting dots, inner portal glow, center icon.
/// Styled similarly to the avatar but with orange/cyan portal theme.
class PortalMarker extends StatefulWidget {
  final double size;
  final VoidCallback? onTap;
  final bool isActive; // Whether the portal has seats available

  const PortalMarker({
    super.key,
    this.size = 60.0,
    this.onTap,
    this.isActive = true,
  });

  @override
  State<PortalMarker> createState() => _PortalMarkerState();
}

class _PortalMarkerState extends State<PortalMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _orbit1;
  late Animation<double> _orbit2;
  late Animation<double> _pulseGlow;
  late Animation<double> _pulseRing;
  late Animation<double> _spinSlow;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat();

    // Orbiting dots (full rotation)
    _orbit1 = Tween<double>(begin: 0.0, end: math.pi * 2).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.8, curve: Curves.linear),
      ),
    );

    _orbit2 = Tween<double>(begin: 0.0, end: -math.pi * 2).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.1, 0.9, curve: Curves.linear),
      ),
    );

    // Glow pulse
    _pulseGlow = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    // Ring pulse
    _pulseRing = Tween<double>(begin: 0.9, end: 1.15).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );

    // Slow spin for inner ring
    _spinSlow = Tween<double>(begin: 0.0, end: math.pi * 2).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 1.0, curve: Curves.linear),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            size: Size(widget.size * 1.6, widget.size * 1.6),
            painter: _PortalPainter(
              orbit1: _orbit1.value,
              orbit2: _orbit2.value,
              glowOpacity: _pulseGlow.value,
              ringScale: _pulseRing.value,
              spin: _spinSlow.value,
              isActive: widget.isActive,
            ),
          );
        },
      ),
    );
  }
}

class _PortalPainter extends CustomPainter {
  final double orbit1;
  final double orbit2;
  final double glowOpacity;
  final double ringScale;
  final double spin;
  final bool isActive;

  _PortalPainter({
    required this.orbit1,
    required this.orbit2,
    required this.glowOpacity,
    required this.ringScale,
    required this.spin,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2;
    final coreRadius = baseRadius * 0.38;

    // === Layer 1: Outer glow halo ===
    final haloPaint = Paint()
      ..color = (isActive ? Colors.orange : Colors.grey).withOpacity(glowOpacity * 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 25);
    canvas.drawCircle(center, coreRadius * 2.8, haloPaint);

    // === Layer 2: Outer pulsing ring ===
    final outerRingRadius = baseRadius * 0.85 * ringScale;
    final outerRingPaint = Paint()
      ..color = (isActive ? Colors.orangeAccent : Colors.grey).withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, outerRingRadius, outerRingPaint);

    // === Layer 3: Orbiting dot 1 ===
    final orbit1Radius = baseRadius * 0.7;
    final dot1X = center.dx + math.cos(orbit1) * orbit1Radius;
    final dot1Y = center.dy + math.sin(orbit1) * orbit1Radius;
    final dot1Paint = Paint()
      ..color = Colors.cyan.withOpacity(0.9)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(Offset(dot1X, dot1Y), 5, dot1Paint);
    // Sharp core
    final dot1Core = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(dot1X, dot1Y), 2.5, dot1Core);

    // === Layer 4: Orbiting dot 2 ===
    final orbit2Radius = baseRadius * 0.6;
    final dot2X = center.dx + math.cos(orbit2) * orbit2Radius;
    final dot2Y = center.dy + math.sin(orbit2) * orbit2Radius;
    final dot2Paint = Paint()
      ..color = Colors.orangeAccent.withOpacity(0.9)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(Offset(dot2X, dot2Y), 4, dot2Paint);
    final dot2Core = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(dot2X, dot2Y), 2, dot2Core);

    // === Layer 5: Inner rotating dashed ring ===
    final innerRingRadius = baseRadius * 0.55;
    final innerRingPaint = Paint()
      ..color = (isActive ? Colors.cyan : Colors.grey).withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(spin);

    // Draw dashed circle
    const dashCount = 12;
    for (int i = 0; i < dashCount; i++) {
      final angle = (math.pi * 2 / dashCount) * i;
      final dashLength = 0.15;
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: innerRingRadius),
        angle,
        dashLength,
        false,
        innerRingPaint,
      );
    }
    canvas.restore();

    // === Layer 6: Portal core (main circle) ===
    final coreGradient = RadialGradient(
      center: const Alignment(-0.2, -0.2),
      colors: isActive
          ? [
              const Color(0xFFFFAB40), // Light orange highlight
              const Color(0xFFFF6D00), // Orange
              const Color(0xFFE65100), // Deep orange
              const Color(0xFFBF360C), // Dark edge
            ]
          : [
              Colors.grey.shade300,
              Colors.grey.shade500,
              Colors.grey.shade700,
              Colors.grey.shade800,
            ],
      stops: const [0.0, 0.3, 0.7, 1.0],
    );
    final corePaint = Paint()
      ..shader = coreGradient.createShader(
        Rect.fromCircle(center: center, radius: coreRadius),
      );
    canvas.drawCircle(center, coreRadius, corePaint);

    // === Layer 7: Core highlight shine ===
    final shineGradient = RadialGradient(
      center: const Alignment(-0.5, -0.5),
      colors: [
        Colors.white.withOpacity(0.5),
        Colors.white.withOpacity(0.0),
      ],
    );
    final shinePaint = Paint()
      ..shader = shineGradient.createShader(
        Rect.fromCircle(
          center: Offset(center.dx - coreRadius * 0.2, center.dy - coreRadius * 0.2),
          radius: coreRadius * 0.6,
        ),
      );
    canvas.drawCircle(
      Offset(center.dx - coreRadius * 0.15, center.dy - coreRadius * 0.15),
      coreRadius * 0.5,
      shinePaint,
    );

    // === Layer 8: Center icon (sharing/car-pool symbol) ===
    final iconPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // Draw a simple "person" icon (circle + arc body)
    final iconCenter = Offset(center.dx, center.dy - coreRadius * 0.1);
    // Head
    canvas.drawCircle(iconCenter, coreRadius * 0.18, Paint()..color = Colors.white);
    // Body arc
    final bodyPath = Path()
      ..moveTo(iconCenter.dx - coreRadius * 0.25, iconCenter.dy + coreRadius * 0.35)
      ..quadraticBezierTo(
        iconCenter.dx,
        iconCenter.dy + coreRadius * 0.55,
        iconCenter.dx + coreRadius * 0.25,
        iconCenter.dy + coreRadius * 0.35,
      );
    canvas.drawPath(bodyPath, iconPaint);

    // === Layer 9: White border ring ===
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, coreRadius + 1, borderPaint);

    // === Layer 10: Small "active" pulse dots on ring ===
    if (isActive) {
      for (int i = 0; i < 4; i++) {
        final angle = (math.pi * 2 / 4) * i + spin * 0.5;
        final px = center.dx + math.cos(angle) * outerRingRadius;
        final py = center.dy + math.sin(angle) * outerRingRadius;
        final dotPaint = Paint()
          ..color = Colors.white.withOpacity(0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
        canvas.drawCircle(Offset(px, py), 2, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PortalPainter oldDelegate) {
    return oldDelegate.orbit1 != orbit1 ||
        oldDelegate.orbit2 != orbit2 ||
        oldDelegate.glowOpacity != glowOpacity ||
        oldDelegate.ringScale != ringScale ||
        oldDelegate.spin != spin ||
        oldDelegate.isActive != isActive;
  }
}
