import 'package:flutter/material.dart';
import 'package:tag_battle_royale/util/faceDetection/face_detection_graph.dart';

class ClosedZonePainter extends CustomPainter {
  final ValueNotifier<Set<int>> facesNotifier;
  final List<Face> faces;

  ClosedZonePainter({
    required this.facesNotifier,
    required this.faces
  }) : super(repaint: facesNotifier);

  @override
  void paint(Canvas canvas, Size size){
    final paintFaces = facesNotifier.value;

    final fillPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    for(final face in faces){
      if(!paintFaces.contains((face.faceID))){continue;}
      final path = Path()..addPolygon(face.polygon, true);
      canvas.drawPath(path, fillPaint);

      final textPainter = TextPainter(
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      final text = "Closed";

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
  bool shouldRepaint(covariant ClosedZonePainter oldDelegate){
    return false;
  }
}