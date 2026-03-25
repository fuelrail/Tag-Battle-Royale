import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import "../faceDetection/face_detection_graph.dart";

// draws the process edges between vertices
class EdgePainter extends CustomPainter{
  final List<Edge> edges;

  EdgePainter({
    required this.edges,
  });

  @override
  void paint(Canvas canvas, Size size){
    final paint = Paint()
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 6.0
    ..color = ui.Color(0xFFFF0000);
    for(int i = 0; i < edges.length; i++){
    canvas.drawLine(edges[i].a.p, edges[i].b.p, paint);
    }
  }

  @override
  bool shouldRepaint(covariant EdgePainter oldDelegate){
    return false;
  }
}