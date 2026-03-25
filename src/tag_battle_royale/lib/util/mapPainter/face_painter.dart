import 'package:flutter/material.dart';
import "../faceDetection/face_detection_graph.dart";

// draws the faces
class FacePainter extends CustomPainter{
  final List<Face> faces;
  final bool drawLabel;

  FacePainter({
    required this.faces,
    this.drawLabel = false,
  });

  @override
  void paint(Canvas canvas, Size size){
    for(int i = 0; i < faces.length; i++){
      // draw face
      final face = faces[i];
      if(face.polygon.length <= 2){continue;}
      final path = Path();
      final first = face.polygon.first;
      path.moveTo(first.dx, first.dy);
      for(int j = 1; j < face.polygon.length; j++){
        final p = face.polygon[j];
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path,Paint()..style = PaintingStyle.fill..color = Colors.primaries[i % Colors.primaries.length].withValues(alpha: 0.3));
      if(!drawLabel){continue;}
      // draw label
      final textPainter = TextPainter(
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      final text = face.name;

      // outline first
      textPainter.text = TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.bold,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = Colors.black,
        ),
      );
      textPainter.layout();
      final offset = face.centroid - Offset(textPainter.width / 2, textPainter.height / 2);
      textPainter.paint(canvas, offset);

      // fill on top
      textPainter.text = TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 40,
          fontWeight: FontWeight.bold,
        ),
      );

      textPainter.layout();
      textPainter.paint(canvas, offset);
    }
  }

  @override
  bool shouldRepaint(covariant FacePainter oldDelegate){
    return false;
  }
}