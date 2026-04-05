import 'package:flutter/material.dart';

class AvatarMarker extends StatelessWidget {
  final double size;
  const AvatarMarker({super.key, this.size = 50.0});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.8, end: 1.0),
      duration: const Duration(seconds: 1),
      curve: Curves.easeInOut,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: Image.asset(
        'assets/images/avatar.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
           return Container(
             width: size,
             height: size,
             decoration: const BoxDecoration(
                color: Colors.blueAccent,
                shape: BoxShape.circle,
             ),
             child: const Icon(Icons.directions_car, color: Colors.white),
           );
        }
      ),
    );
  }
}
