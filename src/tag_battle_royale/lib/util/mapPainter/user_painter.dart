import 'package:flutter/material.dart';

class UserPainter extends CustomPainter {
  final Offset? position;

  UserPainter({required this.position});

  @override
  void paint(Canvas canvas, Size size) {
    if (position == null) return;

    final paint = Paint()
      ..color = const Color(0xFF2196F3)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(position!, 10, paint);
  }

  @override
  bool shouldRepaint(covariant UserPainter oldDelegate) {
    return oldDelegate.position != position;
  }
}