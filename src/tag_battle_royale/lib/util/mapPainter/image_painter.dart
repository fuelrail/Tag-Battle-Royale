import 'package:flutter/material.dart';
import 'dart:ui' as ui;

class ImagePainter extends CustomPainter{
  ImagePainter(this.image);
  final ui.Image image;

  // draws the image
  @override
  void paint(Canvas canvas, Size size){
    canvas.drawImage(image, Offset.zero, Paint());
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}