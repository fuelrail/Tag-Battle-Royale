import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../map_file_handler.dart';
import '../stroke.dart';
import '../faceDetection/face_detection_graph.dart';
import 'image_painter.dart';
import 'stroke_painter.dart';
import 'edge_painter.dart';
import 'face_painter.dart';

class MapPainter extends CustomPainter {
  final ui.Image image;

  final MapFile? map;
  final PlanarGraph? graph;
  final List<Stroke>? strokes;

  final bool drawMode;
  final bool drawLabel;

  MapPainter({
    required this.image,
    this.map,
    this.graph,
    this.strokes,
    this.drawMode = false,
    this.drawLabel = true,
  });

  @override
  void paint(Canvas canvas, Size size){
    ImagePainter(image).paint(canvas, size);

    if(drawMode){
      StrokePainter(strokes ?? []).paint(canvas, size);
    } else {
      final edges = map?.graph.edges ?? graph?.edges ?? [];
      EdgePainter(edges: edges).paint(canvas, size);
    }

    final faces = map?.graph.faces ?? graph?.faces ?? [];
    FacePainter(
      faces: faces,
      drawLabel: drawLabel,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant MapPainter oldDelegate) => true;
}