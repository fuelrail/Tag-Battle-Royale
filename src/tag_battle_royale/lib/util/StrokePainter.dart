import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import '../util/ImageTransform.dart';
import 'Stroke.dart';

class StrokePainter extends CustomPainter{
  StrokePainter(this.strokes, this.imageTransform);

  final ImageTransform imageTransform;
  final List<Stroke> strokes;

  // Centers and scales the Image and points drawn
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeCap = StrokeCap.round;
    for(final stroke in strokes){
      paint
      ..color = stroke.color
      ..strokeWidth = stroke.width;

      for (var i = 0; i < stroke.points.length - 1; i++){
        final p1 = stroke.points[i];
        final p2 = stroke.points[i + 1];
        // scale points with image
        canvas.drawLine(p1, p2, paint);
        }
      }
    }


  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}