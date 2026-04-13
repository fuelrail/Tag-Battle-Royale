import 'package:flutter/material.dart';
import "../faceDetection/face_detection_graph.dart";

class CurrentZonePainter extends CustomPainter {
  final ValueNotifier<int?> faceNotifier;
  final List<Face> faces;
  final Color color;
  final double strokeWidth;

  CurrentZonePainter({
    required this.faceNotifier,
    required this.faces,
    this.color = const Color.fromARGB(255, 255, 255, 255),
    this.strokeWidth = 2,
  }) : super(repaint: faceNotifier);

  @override
  void paint(Canvas canvas, Size size){
    if(faceNotifier.value == null){return;}
    final face = faces.firstWhere((f) => f.faceID == faceNotifier.value);

    if(face.polygon.length < 3) return;

    final path = Path();
    final first = face.polygon.first;
    path.moveTo(first.dx, first.dy);

    for(int i = 1; i < face.polygon.length; i++){
      final p = face.polygon[i];
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
  bool shouldRepaint(covariant CurrentZonePainter oldDelegate){
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}