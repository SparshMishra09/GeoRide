import 'package:flutter/material.dart';

class SharingMarker extends StatelessWidget {
  final double size;
  final VoidCallback onTap;
  
  const SharingMarker({super.key, required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.8, end: 1.2),
        duration: const Duration(milliseconds: 1500),
        curve: Curves.easeInOut,
        builder: (context, scale, child) {
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.blueAccent.withOpacity(0.6),
                blurRadius: 15,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Image.asset(
            'assets/images/portal.png',
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
               return const CircleAvatar(
                 backgroundColor: Colors.blueAccent,
                 child: Icon(Icons.group, color: Colors.white),
               );
            }
          ),
        ),
      ),
    );
  }
}
