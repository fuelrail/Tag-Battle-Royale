import 'package:tag_battle_royale/util/faceDetection/face_detection_graph.dart';
import 'package:flutter/material.dart';

class ClosedZonePainter extends CustomPainter {
  final Iterable<Face> faces;

  ClosedZonePainter({required this.faces});

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    for (final face in faces) {
      final path = Path()..addPolygon(face.polygon, true);
      canvas.drawPath(path, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant ClosedZonePainter oldDelegate) {
    return oldDelegate.faces != faces;
  }
}