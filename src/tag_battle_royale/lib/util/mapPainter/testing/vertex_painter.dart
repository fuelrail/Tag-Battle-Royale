import 'package:flutter/material.dart';
import '../../faceDetection/face_detection_graph.dart';

class VertexPainter extends CustomPainter{
  final List<Vertex> vertice;

  VertexPainter({
    required this.vertice,
  });

  @override
  void paint(Canvas canvas, Size size){
    for(int i = 0; i < vertice.length; i++){
      final p = vertice[i].p;
  
      canvas.drawCircle(p, 4, Paint());
    }
  }

  @override
  bool shouldRepaint(covariant VertexPainter oldDelegate){
    return false;
  }
}