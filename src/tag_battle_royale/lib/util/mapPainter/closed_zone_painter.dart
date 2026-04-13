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
    }
  }

  @override
  bool shouldRepaint(covariant ClosedZonePainter oldDelegate){
    return false;
  }
}