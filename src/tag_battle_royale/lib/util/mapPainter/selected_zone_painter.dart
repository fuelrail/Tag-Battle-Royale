import 'package:flutter/material.dart';
import "../faceDetection/face_detection_graph.dart";

class SelectedZonePainter extends CustomPainter {
  final List<Face> faces;

  SelectedZonePainter({
    required this.faces,
  });

  @override
  void paint(Canvas canvas, Size size){
    final fillPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    for(int i = 0; i < faces.length; i++){
      final face = faces[i];

      final path = Path()..addPolygon(face.polygon, true);
      canvas.drawPath(path, fillPaint);

      final text = '${i + 1}';

      textPainter.text = TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = Colors.black,
        ),
      );
      textPainter.layout();

      final offset = face.centroid -
          Offset(textPainter.width / 2, textPainter.height / 2);
      textPainter.paint(canvas, offset);

      textPainter.text = TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, offset);
    }
  }

  @override
  bool shouldRepaint(covariant SelectedZonePainter oldDelegate){
    return oldDelegate.faces != faces;
  }
}