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

void main(){
  final fd = FaceDetector();

  final List<Stroke> strokes = [
    Stroke(index:0, points:[
      const ui.Offset(705.6,607.1),
      const ui.Offset(679.6,594.9),
      const ui.Offset(651.2,592.4),
      const ui.Offset(618.0,597.6),
      const ui.Offset(583.9,611.1),
      const ui.Offset(551.0,629.2),
      const ui.Offset(521.2,647.4),
      const ui.Offset(493.2,667.9),
      const ui.Offset(464.5,694.8),
      const ui.Offset(434.7,725.2),
      const ui.Offset(407.5,758.6),
      const ui.Offset(382.7,796.7),
      const ui.Offset(361.3,837.7),
      const ui.Offset(344.7,882.8),
      const ui.Offset(333.9,930.8),
      const ui.Offset(325.7,981.8),
      const ui.Offset(321.2,1035.1),
      const ui.Offset(320.9,1089.6),
      const ui.Offset(324.3,1151.1),
      const ui.Offset(331.7,1216.1),
      const ui.Offset(345.1,1266.6),
      const ui.Offset(364.3,1311.1),
      const ui.Offset(393.0,1352.7),
      const ui.Offset(423.8,1388.5),
      const ui.Offset(459.9,1417.2),
      const ui.Offset(497.4,1437.8),
      const ui.Offset(540.3,1450.7),
      const ui.Offset(581.7,1454.9),
      const ui.Offset(629.4,1448.5),
      const ui.Offset(678.2,1429.2),
      const ui.Offset(727.2,1393.5),
      const ui.Offset(773.6,1345.0),
      const ui.Offset(813.0,1281.2),
      const ui.Offset(846.5,1210.9),
      const ui.Offset(871.3,1133.0),
      const ui.Offset(884.3,1053.3),
      const ui.Offset(885.4,976.0),
      const ui.Offset(875.5,902.1),
      const ui.Offset(854.2,837.6),
      const ui.Offset(822.8,786.0),
      const ui.Offset(784.6,738.5),
      const ui.Offset(740.9,695.1),
      const ui.Offset(694.0,658.2),
      const ui.Offset(643.6,621.9),
      const ui.Offset(594.0,593.7),
      const ui.Offset(547.1,570.8),
      const ui.Offset(506.2,552.0),
      const ui.Offset(475.0,537.4),
      const ui.Offset(453.6,522.9),
      const ui.Offset(444.7,509.3),
      const ui.Offset(446.1,499.1),
      const ui.Offset(447.7,496.9),
    ]),
    Stroke(index:3, points:[
      const ui.Offset(829.8,639.3),
      const ui.Offset(820.3,658.6),
      const ui.Offset(807.6,682.6),
      const ui.Offset(791.5,710.7),
      const ui.Offset(775.7,741.2),
      const ui.Offset(760.4,771.1),
      const ui.Offset(745.4,806.2),
      const ui.Offset(731.2,840.2),
      const ui.Offset(715.6,873.6),
      const ui.Offset(703.7,905.9),
      const ui.Offset(692.1,938.1),
      const ui.Offset(681.1,966.2),
      const ui.Offset(672.1,993.7),
      const ui.Offset(665.0,1017.2),
      const ui.Offset(658.1,1038.9),
      const ui.Offset(651.0,1059.4),
      const ui.Offset(643.4,1077.0),
      const ui.Offset(636.2,1096.3),
      const ui.Offset(630.2,1114.5),
      const ui.Offset(621.7,1132.6),
      const ui.Offset(613.3,1153.1),
      const ui.Offset(603.8,1173.0),
      const ui.Offset(594.6,1190.0),
      const ui.Offset(586.1,1204.7),
      const ui.Offset(578.2,1216.4),
      const ui.Offset(571.6,1227.5),
      const ui.Offset(565.3,1237.5),
      const ui.Offset(558.5,1245.1),
      const ui.Offset(552.4,1252.1),
      const ui.Offset(546.6,1258.0),
      const ui.Offset(542.1,1263.3),
      const ui.Offset(538.2,1266.8),
      const ui.Offset(535.3,1270.9),
      const ui.Offset(532.6,1275.0),
      const ui.Offset(530.0,1278.5),
      const ui.Offset(528.1,1283.8),
      const ui.Offset(526.3,1287.9),
      const ui.Offset(524.7,1292.6),
      const ui.Offset(523.4,1297.3),
      const ui.Offset(522.3,1302.0),
      const ui.Offset(521.0,1307.2),
      const ui.Offset(519.7,1313.1),
      const ui.Offset(518.1,1317.8),
      const ui.Offset(517.3,1322.5),
      const ui.Offset(516.3,1326.6),
      const ui.Offset(515.0,1330.7),
      const ui.Offset(514.4,1334.2),
      const ui.Offset(513.9,1337.7),
      const ui.Offset(513.4,1339.5),
      const ui.Offset(512.6,1341.2),
      const ui.Offset(513.6,1341.8),
      const ui.Offset(513.4,1341.8),
      const ui.Offset(514.2,1341.8),
      const ui.Offset(515.0,1342.4),
      const ui.Offset(515.7,1341.8),
      const ui.Offset(516.3,1340.0),
      const ui.Offset(516.8,1338.3),
      const ui.Offset(517.9,1336.5),
      const ui.Offset(518.6,1334.8),
      const ui.Offset(519.4,1331.8),
      const ui.Offset(520.2,1328.3),
      const ui.Offset(521.0,1324.8),
      const ui.Offset(522.1,1320.7),
      const ui.Offset(523.9,1317.8),
      const ui.Offset(525.0,1313.7),
      const ui.Offset(526.3,1309.6),
      const ui.Offset(527.9,1305.5),
      const ui.Offset(530.5,1299.6),
      const ui.Offset(534.5,1287.9),
      const ui.Offset(538.4,1273.8),
    ]),
  ];


  fd.addAllStrokes(strokes);
  fd.rebuild();

  print("faces + ${fd.graph!.faces.length}");
  print("\nVertices\n");
  for(final v in fd.graph!.vertices){
    print("${v}");
  }
  print("\nEdges\n");
  for(final e in fd.graph!.edges){
    print("${e.a} -> ${e.b}");
  }
}


