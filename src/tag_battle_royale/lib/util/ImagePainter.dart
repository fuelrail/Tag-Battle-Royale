import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import '../util/ImageTransform.dart';

class ImagePainter extends CustomPainter{
  ImagePainter(this.image, this.imageTransform);
  final ImageTransform imageTransform;
  final ui.Image image;

  // Centers and scales the Image
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    canvas.drawImageRect(image, imageTransform.imageRec, imageTransform.canvasRec, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}