import 'package:flutter/material.dart';
import "../faceDetection/face_detection_segment.dart";

class SegmentPainter extends CustomPainter{
  final List<SegmentData> segments;

  SegmentPainter({
    required this.segments,
  });

  @override
  void paint(Canvas canvas, Size size){
    final path = Path();
    final first = segments[0].a;
    path.moveTo(first.dx, first.dy);
    for(int i = 0; i < segments.length; i++){
      final p = segments[i].b;
      if(i != 0 && segments[i].ref.strokeIndex != segments[i - 1].ref.strokeIndex){
        path.moveTo(p.dx, p.dy);
        continue;
      }
      path.lineTo(p.dx, p.dy);
    }
    path.close();

    canvas.drawPath(path,Paint()..style = PaintingStyle.stroke..color = Colors.blue..strokeWidth=2);
  }

  @override
  bool shouldRepaint(covariant SegmentPainter oldDelegate){
    return false;
  }
}