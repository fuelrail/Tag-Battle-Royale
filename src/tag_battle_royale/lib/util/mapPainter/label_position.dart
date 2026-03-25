import 'dart:math' as math;
import 'dart:ui' as ui;
import "../faceDetection/face_detection_point.dart";

// Determines where to put the label for a face by find the farthest point from any edge
ui.Offset findPoleOfInaccessibility(List<ui.Offset> polygon, PointBuilder pointBuilder){
  if(polygon.length < 3){
    throw ArgumentError('Polygon must have at least 3 points.');
  }

  final bounds = _getBounds(polygon);
  final minX = bounds.$1;
  final minY = bounds.$2;
  final maxX = bounds.$3;
  final maxY = bounds.$4;

  final width = maxX - minX;
  final height = maxY - minY;
  final cellSize = math.min(width, height);

  if(cellSize <= pointBuilder.epsilon){
    return polygon.first;
  }
  final h = cellSize / 2.0;
  final queue = <Map<String, double>>[];

  void push(Map<String, double> cell){
    queue.add(cell);
    queue.sort((a, b) => b['max']!.compareTo(a['max']!));
  }
  Map<String, double> pop(){
    return queue.removeAt(0);
  }
  Map<String, double> makeCell(double x, double y, double h){
    final d = _pointToPolygonSignedDistance(ui.Offset(x, y), polygon,pointBuilder);
    return {
      'x': x,
      'y': y,
      'h': h,
      'd': d,
      'max': d + h * math.sqrt2,
    };
  }
  // initial grid
  for(double x = minX; x < maxX; x += cellSize){
    for(double y = minY; y < maxY; y += cellSize){
      push(makeCell(x + h, y + h, h));
    }
  }
  var bestCell = _centroidCell(polygon, pointBuilder);
  final boxCentre = ui.Offset(minX + width / 2, minY + height / 2);
  final boxCell = makeCell(boxCentre.dx, boxCentre.dy, 0);

  if(boxCell['d']! > bestCell['d']!){
    bestCell = boxCell;
  }
  while(queue.isNotEmpty){
    final cell = pop();
    if(cell['d']! > bestCell['d']!){
      bestCell = cell;
    }
    if(cell['max']! - bestCell['d']! <= 1) continue;

    final h2 = cell['h']! / 2;
    final children = [
      makeCell(cell['x']! - h2, cell['y']! - h2, h2),
      makeCell(cell['x']! + h2, cell['y']! - h2, h2),
      makeCell(cell['x']! - h2, cell['y']! + h2, h2),
      makeCell(cell['x']! + h2, cell['y']! + h2, h2),
    ];

    for(final c in children){
      push(c);
    }
  }
  return ui.Offset(bestCell['x']!, bestCell['y']!);
}
// returns the square that contains the polygon
(double, double, double, double) _getBounds(List<ui.Offset> polygon){
  double minX = polygon.first.dx;
  double minY = polygon.first.dy;
  double maxX = polygon.first.dx;
  double maxY = polygon.first.dy;

  for(final p in polygon){
    if(p.dx < minX) minX = p.dx;
    if(p.dy < minY) minY = p.dy;
    if(p.dx > maxX) maxX = p.dx;
    if(p.dy > maxY) maxY = p.dy;
  }

  return (minX, minY, maxX, maxY);
}
// creates a cell
Map<String, double> _centroidCell(List<ui.Offset> polygon, PointBuilder pointBuilder){
  double area = 0;
  double cx = 0;
  double cy = 0;

  for(int i = 0; i < polygon.length; i++){
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    final f = crossProduct(a, b);
    area += f;
    cx += (a.dx + b.dx) * f;
    cy += (a.dy + b.dy) * f;
  }

  ui.Offset c;
  if(area.abs() <= pointBuilder.epsilon){
    c = centroid(polygon);
  }else{
    c = ui.Offset(cx / (3 * area), cy / (3 * area));
  }

  final d = _pointToPolygonSignedDistance(c, polygon, pointBuilder);

  return {
    'x': c.dx,
    'y': c.dy,
    'h': 0,
    'd': d,
    'max': d,
  };
}
// returns the distance to the closest edge in a polygon, negative if outside the polygon
double _pointToPolygonSignedDistance(ui.Offset point, List<ui.Offset> polygon, PointBuilder pointBuilder){
  bool inside = false;
  double minDist = double.infinity;

  for(int i = 0, j = polygon.length - 1; i < polygon.length; j = i++){
    final a = polygon[j];
    final b = polygon[i];

    if(((a.dy > point.dy) != (b.dy > point.dy)) && (point.dx < (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx)){
      inside = !inside;
    }

    final d = pointBuilder.pointLineDistance(point, a, b);
    if(d < minDist) minDist = d;
  }

  return inside ? minDist : -minDist;
}