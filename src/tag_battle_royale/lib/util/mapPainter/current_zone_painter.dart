import 'package:flutter/material.dart';
import "../faceDetection/face_detection_graph.dart";

class CurrentZonePainter extends CustomPainter {
  final Face? face;
  final Color color;
  final double strokeWidth;

  CurrentZonePainter({
    required this.face,
    this.color = const Color.fromARGB(255, 255, 255, 255),
    this.strokeWidth = 2,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (face == null) return;
    if (face!.polygon.length < 2) return;

    final path = Path();
    final first = face!.polygon.first;
    path.moveTo(first.dx, first.dy);

    for (int i = 1; i < face!.polygon.length; i++) {
      final p = face!.polygon[i];
      path.lineTo(p.dx, p.dy);
    }

    path.close();

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CurrentZonePainter oldDelegate) {
    return oldDelegate.face != face ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}