import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Simple 2D circle avatar with wavy pulse animations.
/// No human features, no direction indicator — just a clean animated circle.
class AvatarMarker extends StatefulWidget {
  final double size;

  const AvatarMarker({
    super.key,
    this.size = 60.0,
  });

  @override
  State<AvatarMarker> createState() => _AvatarMarkerState();
}

class _AvatarMarkerState extends State<AvatarMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulse1;
  late Animation<double> _pulse2;
  late Animation<double> _pulse3;
  late Animation<double> _glowOpacity;
  late Animation<double> _glowSize;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat();

    // Three layered pulse waves (staggered)
    _pulse1 = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _pulse2 = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.15, 0.65, curve: Curves.easeOut),
      ),
    );

    _pulse3 = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.8, curve: Curves.easeOut),
      ),
    );

    // Glow: continuous fade in/out
    _glowOpacity = Tween<double>(begin: 0.2, end: 0.7).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _glowSize = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size * _glowSize.value, widget.size * _glowSize.value),
          painter: _CircleAvatarPainter(
            pulse1: _pulse1.value,
            pulse2: _pulse2.value,
            pulse3: _pulse3.value,
            glowOpacity: _glowOpacity.value,
          ),
        );
      },
    );
  }
}

class _CircleAvatarPainter extends CustomPainter {
  final double pulse1;
  final double pulse2;
  final double pulse3;
  final double glowOpacity;

  _CircleAvatarPainter({
    required this.pulse1,
    required this.pulse2,
    required this.pulse3,
    required this.glowOpacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2;
    final coreRadius = baseRadius * 0.45;

    // === Layer 1: Outermost wavy ring ===
    final outerRadius = baseRadius * (0.85 + pulse3 * 0.4);
    final outerPaint = Paint()
      ..color = Colors.cyan.withOpacity(glowOpacity * 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, outerRadius, outerPaint);

    // === Layer 2: Middle wavy ring ===
    final midRadius = baseRadius * (0.65 + pulse2 * 0.35);
    final midPaint = Paint()
      ..color = Colors.blueAccent.withOpacity(glowOpacity * 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, midRadius, midPaint);

    // === Layer 3: Inner wavy ring ===
    final innerRadius = baseRadius * (0.5 + pulse1 * 0.2);
    final innerPaint = Paint()
      ..color = Colors.blue.withOpacity(glowOpacity * 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, innerRadius, innerPaint);

    // === Layer 4: Soft glow halo ===
    final glowPaint = Paint()
      ..color = Colors.cyan.withOpacity(glowOpacity * 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    canvas.drawCircle(center, coreRadius * 2.0, glowPaint);

    // === Layer 5: Main body circle ===
    final bodyGradient = RadialGradient(
      center: const Alignment(-0.25, -0.25),
      colors: [
        const Color(0xFF4FC3F7), // Light blue highlight
        const Color(0xFF2196F3), // Main blue
        const Color(0xFF1565C0), // Deep blue shadow
        const Color(0xFF0D47A1), // Dark edge
      ],
      stops: const [0.0, 0.3, 0.7, 1.0],
    );
    final bodyPaint = Paint()
      ..shader = bodyGradient.createShader(
        Rect.fromCircle(center: center, radius: coreRadius),
      );
    canvas.drawCircle(center, coreRadius, bodyPaint);

    // === Layer 6: Highlight shine (top-left) ===
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
          radius: coreRadius * 0.7,
        ),
      );
    canvas.drawCircle(
      Offset(center.dx - coreRadius * 0.15, center.dy - coreRadius * 0.15),
      coreRadius * 0.55,
      shinePaint,
    );

    // === Layer 7: Crisp white border ===
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, coreRadius + 1, borderPaint);

    // === Layer 8: Inner dot (center accent) ===
    final dotPaint = Paint()
      ..color = Colors.white.withOpacity(0.8);
    canvas.drawCircle(center, coreRadius * 0.12, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _CircleAvatarPainter oldDelegate) {
    return oldDelegate.pulse1 != pulse1 ||
        oldDelegate.pulse2 != pulse2 ||
        oldDelegate.pulse3 != pulse3 ||
        oldDelegate.glowOpacity != glowOpacity;
  }
}
