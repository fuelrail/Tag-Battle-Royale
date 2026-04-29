import 'dart:ui' as ui;

import '../stroke.dart';
import 'face_detection_point.dart';
import 'face_detection_stroke.dart';
import 'face_detection_segment.dart';
import 'face_detection_graph.dart';

class FaceDetector {
  final double cellSize;
  final double mergeTolerance;
  final double snapTolerance;
  final double simplifyTolerance;
  final double endpointToSegmentTolerance;
  final double minimumFaceArea;
  final double epsilon;
  PlanarGraph? graph;
  List<Stroke>? strokes;
  List<SegmentData>? segments;


  late final PointBuilder pointBuilder;
  late final StrokeBuilder strokeBuilder;
  late final SegmentBuilder segmentBuilder;
  late final GraphBuilder graphBuilder;

  final List<Stroke> rawStrokes = [];

  FaceDetector({
    this.cellSize = 24.0,
    this.mergeTolerance = 4.0,
    this.snapTolerance = 6.0,
    this.simplifyTolerance = 1.5,
    this.endpointToSegmentTolerance = 10.0,
    this.minimumFaceArea = 200,
    this.epsilon = 1e-6,
  }){
    pointBuilder = PointBuilder(epsilon:epsilon, mergeTolerance:mergeTolerance);
    strokeBuilder = StrokeBuilder(snapTolerance:snapTolerance, simplifyTolerance:simplifyTolerance, epsilon:epsilon, pointBuilder:pointBuilder);
    segmentBuilder = SegmentBuilder(cellSize:cellSize, mergeTolerance:mergeTolerance, endpointToSegmentTolerance:endpointToSegmentTolerance, epsilon:epsilon, pointBuilder:pointBuilder);
    graphBuilder = GraphBuilder(mergeTolerance:mergeTolerance,minimumFaceArea: minimumFaceArea, epsilon:epsilon, pointBuilder:pointBuilder, segmentBuilder:segmentBuilder);
  }

   void clear(){
    rawStrokes.clear();
    graph = null;
    strokes = null;
    segments = null;
  }

  void addStroke(Stroke stroke){
    rawStrokes.add(_cloneStroke(stroke));
  }

  void addAllStrokes(Iterable<Stroke> newStrokes){
    for (final stroke in newStrokes){
      rawStrokes.add(_cloneStroke(stroke));
    }
  }

  void removeLastStroke(){
    if(rawStrokes.isEmpty){return;}
    rawStrokes.removeLast();
  }

  void rebuild(){
    if(rawStrokes.isEmpty){
      graph = null;
      strokes = null;
      segments = null;
      return;
    }

    strokes = strokeBuilder.prepareStrokes(rawStrokes);
    segments = segmentBuilder.buildSegments(strokes!);
    final intersections = segmentBuilder.findIntersections(segments!);
    graph = graphBuilder.buildPlanarGraph(segments!, intersections);
  }

  void replaceAllStrokes(Iterable<Stroke> newStrokes){
    clear();
    addAllStrokes(newStrokes);
    rebuild();
  }

  void deleteFace(Face f){
    final currentGraph = graph;
    if(currentGraph == null){return;}
    graph = graphBuilder.deleteFace(currentGraph, f);
  }

  Stroke _cloneStroke(Stroke stroke){
    return Stroke(
      index: stroke.index,
      width: stroke.width,
      color: stroke.color,
      points: stroke.points
          .map((p) => ui.Offset(p.dx, p.dy))
          .toList(),
    );
  }
}
