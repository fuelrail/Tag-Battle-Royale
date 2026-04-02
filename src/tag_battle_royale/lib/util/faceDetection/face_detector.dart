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

  void addStroke(Stroke stroke){
    List<ui.Offset> newPoints = stroke.points.map((p) => ui.Offset(p.dx, p.dy)).toList();
    rawStrokes.add(
      Stroke(index:stroke.index, points:newPoints, width:stroke.width, color:stroke.color)
    );
  }

  void removeStroke(){
    rawStrokes.removeLast();
  }

  void buildGraphAndFindFaces(){
    strokes = strokeBuilder.prepareStrokes(rawStrokes);
    segments = segmentBuilder.buildSegments(strokes!);
    final intersections = segmentBuilder.findIntersections(segments!);
    graph = graphBuilder.buildPlanarGraph(segments!, intersections);
  }

  void deleteFace(Face f){
    graph = graphBuilder.deleteFace(graph!, f);
  }
}

// test cases
void main(){

  // ];

  final strokes = <Stroke>[
      Stroke(index:0, points:[
        const ui.Offset(225.7,1389.6),
      const ui.Offset(226.7,1388.0),
      const ui.Offset(228.2,1384.3),
      const ui.Offset(236.3,1313.8),
      const ui.Offset(235.2,1238.7),
      const ui.Offset(233.3,1155.6),
      const ui.Offset(235.7,1074.7),
      const ui.Offset(238.6,985.7),
      const ui.Offset(239.4,896.7),
      const ui.Offset(240.2,731.4),
      const ui.Offset(238.9,660.4),
      const ui.Offset(240.4,599.4),
      const ui.Offset(239.2,548.4),
      const ui.Offset(239.9,508.5),
      const ui.Offset(238.6,482.7),
      const ui.Offset(236.5,461.2),
      const ui.Offset(235.6,457.9),
      const ui.Offset(234.1,456.2),
      const ui.Offset(232.2,453.9),
      const ui.Offset(231.1,452.9),
      const ui.Offset(230.2,452.4),
      const ui.Offset(229.4,452.7),
      const ui.Offset(235.6,449.8),
      const ui.Offset(242.1,446.5),
      const ui.Offset(254.2,441.1),
      const ui.Offset(280.7,430.9),
      const ui.Offset(363.4,405.2),
      const ui.Offset(409.3,394.7),
      const ui.Offset(454.9,387.7),
      const ui.Offset(502.1,379.5),
      const ui.Offset(546.1,371.3),
      const ui.Offset(586.7,363.6),
      const ui.Offset(623.7,358.9),
      const ui.Offset(654.0,353.7),
      const ui.Offset(679.6,353.1),
      const ui.Offset(695.2,351.3),
      const ui.Offset(713.9,354.0),
      const ui.Offset(717.7,356.3),
      const ui.Offset(722.4,371.2),
      const ui.Offset(725.7,392.8),
      const ui.Offset(728.2,427.3),
      const ui.Offset(731.9,469.4),
      const ui.Offset(748.5,566.1),
      const ui.Offset(761.2,621.1),
      const ui.Offset(776.7,682.0),
      const ui.Offset(816.5,815.0),
      const ui.Offset(837.8,869.6),
      const ui.Offset(856.3,917.7),
      const ui.Offset(870.6,958.7),
      const ui.Offset(879.8,998.0),
      const ui.Offset(885.4,1034.3),
      const ui.Offset(889.1,1071.2),
      const ui.Offset(889.4,1093.8),
      const ui.Offset(891.6,1112.2),
      const ui.Offset(895.4,1131.6),
      const ui.Offset(900.3,1150.3),
      const ui.Offset(910.0,1188.9),
      const ui.Offset(915.1,1207.0),
      const ui.Offset(918.6,1224.3),
      const ui.Offset(920.3,1238.4),
      const ui.Offset(923.3,1261.2),
      const ui.Offset(924.8,1269.7),
      const ui.Offset(926.8,1277.1),
      const ui.Offset(928.1,1283.2),
      const ui.Offset(929.0,1287.9),
      const ui.Offset(923.9,1291.1),
      const ui.Offset(916.9,1291.4),
      const ui.Offset(904.4,1292.7),
      const ui.Offset(886.5,1296.6),
      const ui.Offset(865.9,1300.6),
      const ui.Offset(838.1,1306.1),
      const ui.Offset(807.5,1311.0),
      const ui.Offset(774.0,1317.5),
      const ui.Offset(739.0,1325.1),
      const ui.Offset(702.3,1332.1),
      const ui.Offset(663.6,1338.6),
      const ui.Offset(625.1,1343.8),
      const ui.Offset(585.0,1346.8),
      const ui.Offset(545.7,1349.1),
      const ui.Offset(510.1,1348.6),
      const ui.Offset(475.3,1348.0),
      const ui.Offset(442.6,1343.9),
      const ui.Offset(411.5,1338.6),
      const ui.Offset(386.1,1333.3),
      const ui.Offset(362.7,1331.0),
      const ui.Offset(342.2,1329.2),
      const ui.Offset(325.4,1328.7),
      const ui.Offset(308.7,1329.8),
      const ui.Offset(292.1,1328.8),
      const ui.Offset(277.1,1325.7),
      const ui.Offset(259.8,1322.6),
      const ui.Offset(242.8,1321.3),
      const ui.Offset(225.9,1321.0),
      const ui.Offset(209.0,1321.4),
      const ui.Offset(192.2,1322.0),
      const ui.Offset(176.7,1320.6),
      const ui.Offset(164.0,1320.2),
      const ui.Offset(155.3,1320.4),
      const ui.Offset(151.6,1318.1),
    ]),
    Stroke(index:1, points:[
      const ui.Offset(410.5,1123.0),
      const ui.Offset(411.3,1123.6),
      const ui.Offset(411.7,1125.0),
      const ui.Offset(412.1,1125.9),
      const ui.Offset(413.6,1128.2),
      const ui.Offset(415.5,1131.5),
      const ui.Offset(422.6,1142.3),
      const ui.Offset(440.3,1171.5),
      const ui.Offset(455.8,1199.0),
      const ui.Offset(472.9,1227.7),
      const ui.Offset(493.0,1254.1),
      const ui.Offset(514.1,1281.0),
      const ui.Offset(535.1,1307.4),
      const ui.Offset(559.1,1333.8),
      const ui.Offset(582.6,1360.1),
      const ui.Offset(602.1,1379.8),
      const ui.Offset(616.8,1397.5),
      const ui.Offset(628.9,1413.4),
      const ui.Offset(638.5,1427.1),
      const ui.Offset(647.5,1439.5),
      const ui.Offset(657.9,1452.9),
      const ui.Offset(669.1,1470.1),
      const ui.Offset(679.7,1485.9),
      const ui.Offset(688.6,1496.4),
      const ui.Offset(700.3,1507.6),
      const ui.Offset(705.8,1510.6),
      const ui.Offset(711.8,1511.4),
      const ui.Offset(716.8,1511.7),
      const ui.Offset(723.3,1512.0),
      const ui.Offset(731.7,1512.9),
      const ui.Offset(744.0,1514.1),
      const ui.Offset(758.5,1517.0),
      const ui.Offset(774.3,1520.8),
      const ui.Offset(787.6,1523.5),
      const ui.Offset(798.5,1525.6),
      const ui.Offset(806.6,1525.5),
      const ui.Offset(811.8,1522.9),
      const ui.Offset(811.7,1501.8),
      const ui.Offset(806.3,1472.1),
      const ui.Offset(797.6,1430.2),
      const ui.Offset(791.8,1379.9),
      const ui.Offset(790.0,1323.1),
      const ui.Offset(790.2,1266.2),
      const ui.Offset(792.8,1212.9),
      const ui.Offset(796.5,1171.2),
      const ui.Offset(798.7,1154.6),
    ]),
    Stroke(index:2, points:[
      const ui.Offset(387.3,1406.6),
      const ui.Offset(386.8,1401.1),
      const ui.Offset(387.6,1380.0),
      const ui.Offset(394.7,1305.0),
      const ui.Offset(404.2,1221.8),
      const ui.Offset(413.9,1135.7),
      const ui.Offset(425.3,1064.1),
      const ui.Offset(436.3,1017.7),
      const ui.Offset(436.4,1017.5),
    ]),
  ];

  // final strokes = <Stroke>[
  //   Stroke(index:0, points:[
  //     const ui.Offset(312.1,1032.1),
  //     const ui.Offset(367.3,1029.8),
  //     const ui.Offset(416.1,1024.5),
  //     const ui.Offset(467.8,1019.3),
  //     const ui.Offset(516.3,1013.4),
  //     const ui.Offset(559.5,1008.1),
  //     const ui.Offset(636.9,998.2),
  //     const ui.Offset(668.2,994.1),
  //     const ui.Offset(699.1,991.1),
  //     const ui.Offset(722.0,990.0),
  //     const ui.Offset(743.6,989.4),
  //     const ui.Offset(765.5,988.9),
  //     const ui.Offset(784.0,988.7),
  //     const ui.Offset(799.1,989.7),
  //     const ui.Offset(814.0,990.5),
  //     const ui.Offset(823.3,991.4),
  //     const ui.Offset(830.2,992.9),
  //     const ui.Offset(834.5,994.4),
  //     const ui.Offset(836.8,995.2),
  //     const ui.Offset(838.2,996.1),
  //     const ui.Offset(839.4,996.1),
  //     const ui.Offset(839.8,996.4),
  //     const ui.Offset(838.8,995.8),
  //     const ui.Offset(837.9,994.6),
  //     const ui.Offset(837.0,993.5),
  //     const ui.Offset(834.8,989.4),
  //     const ui.Offset(831.4,981.5),
  //     const ui.Offset(825.2,962.5),
  //     const ui.Offset(814.0,924.5),
  //     const ui.Offset(802.1,881.8),
  //     const ui.Offset(790.8,836.7),
  //     const ui.Offset(786.5,792.1),
  //     const ui.Offset(781.8,749.9),
  //     const ui.Offset(779.9,710.7),
  //     const ui.Offset(778.1,672.6),
  //     const ui.Offset(776.0,640.3),
  //     const ui.Offset(772.6,613.3),
  //     const ui.Offset(768.0,593.3),
  //     const ui.Offset(764.7,582.3),
  //     const ui.Offset(761.6,572.2),
  //     const ui.Offset(758.7,561.6),
  //     const ui.Offset(755.2,554.0),
  //     const ui.Offset(752.9,548.2),
  //     const ui.Offset(748.4,544.4),
  //     const ui.Offset(742.8,542.3),
  //     const ui.Offset(735.5,541.7),
  //     const ui.Offset(724.1,542.6),
  //     const ui.Offset(708.4,544.8),
  //     const ui.Offset(689.4,546.1),
  //     const ui.Offset(667.2,548.1),
  //     const ui.Offset(639.9,549.9),
  //     const ui.Offset(608.7,551.7),
  //     const ui.Offset(575.2,552.3),
  //     const ui.Offset(540.2,552.3),
  //     const ui.Offset(506.9,551.1),
  //     const ui.Offset(448.6,551.1),
  //     const ui.Offset(424.1,551.1),
  //     const ui.Offset(401.2,550.5),
  //     const ui.Offset(382.1,551.1),
  //     const ui.Offset(365.3,551.7),
  //     const ui.Offset(351.4,552.3),
  //     const ui.Offset(340.8,552.9),
  //     const ui.Offset(332.2,558.4),
  //     const ui.Offset(327.2,564.3),
  //     const ui.Offset(324.1,571.0),
  //     const ui.Offset(324.7,582.2),
  //     const ui.Offset(327.9,606.5),
  //     const ui.Offset(334.6,641.2),
  //     const ui.Offset(344.0,682.1),
  //     const ui.Offset(354.3,729.0),
  //     const ui.Offset(365.1,776.4),
  //     const ui.Offset(375.4,824.5),
  //     const ui.Offset(384.9,869.0),
  //     const ui.Offset(394.7,910.1),
  //     const ui.Offset(402.1,946.4),
  //     const ui.Offset(407.1,976.3),
  //     const ui.Offset(410.5,999.2),
  //     const ui.Offset(412.6,1019.3),
  //     const ui.Offset(413.0,1032.3),
  //     const ui.Offset(413.3,1043.2),
  //     const ui.Offset(413.7,1050.9),
  //     const ui.Offset(412.5,1057.1),
  //     const ui.Offset(415.2,1061.4),
  //     const ui.Offset(415.5,1064.4),
  //     const ui.Offset(412.4,1066.4),
  //     const ui.Offset(411.3,1067.3),
  //     const ui.Offset(411.1,1068.0),
  //     const ui.Offset(411.9,1068.2),
  //     const ui.Offset(415.0,1066.7),
  //   ]),
  // ];
  final detector = FaceDetector();

  for(Stroke stroke in strokes){
    detector.addStroke(stroke);
  }

  detector.buildGraphAndFindFaces();
  if(detector.graph != null){
    print('Vertices:${detector.graph!.vertices.length}');
    print('Edges:${detector.graph!.edges.length}');
    print('Faces:${detector.graph!.faces.length}');

    // for(final v in detector.graph!.vertices){
    //   print(v.p);
    //   for(final e in v.outgoing){
    //     print("to " + e.to.p.toString());
    //   }
    // }
  }
}


