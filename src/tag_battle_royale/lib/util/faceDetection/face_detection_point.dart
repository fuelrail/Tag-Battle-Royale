import 'dart:math' as math;
import 'dart:ui' as ui;

class PointBuilder {
  final double epsilon;
  final double mergeTolerance;

  const PointBuilder({this.epsilon = 1e-6, required this.mergeTolerance});

  // checks if the distance between two points is within a tolerance
  bool samePoint(ui.Offset a, ui.Offset b, [double? tol]){
    final t = tol ?? mergeTolerance;
    return distanceSquared(a, b) <= t * t;
  }

  // shortest distance from a point p to line ab by projecting p onto ab
  double pointLineDistance(ui.Offset point, ui.Offset a, ui.Offset b){
    final ab = b - a;
    final denom = ab.dx * ab.dx + ab.dy * ab.dy;
    // if segment too small return distance to a
    if(denom <= epsilon) return math.sqrt(distanceSquared(point, a));

    final t = ((point.dx - a.dx) * ab.dx + (point.dy - a.dy) * ab.dy) / denom;
    final clamped = t.clamp(0.0, 1.0);
    final proj = ui.Offset(a.dx + clamped * ab.dx, a.dy + clamped * ab.dy);
    return math.sqrt(distanceSquared(point, proj));
  }

 // converts a point into a String key for hashing
  String pointKey(ui.Offset p, [double? tol]){
    final t = tol ?? mergeTolerance;
    final x = (p.dx / t).round();
    final y = (p.dy / t).round();
    return '$x:$y';
  }

  // groups similar points together with tolerance t
  List<ui.Offset> clusterPoints(List<ui.Offset> points, [double? tol]){
    final t = tol ?? mergeTolerance;
    final clusters = <PointCluster>[];

    for(final point in points){
      bool placed = false;
      for(final cluster in clusters){
        if(samePoint(point, cluster.centroid, t)){
          cluster.add(point);
          placed = true;
          break;
        }
      }
      if(!placed){
        clusters.add(PointCluster(point));
      }
    }
    return clusters.map((c) => c.centroid).toList();
  }
}

// distance squared between two points using matrix multiplication
double distanceSquared(ui.Offset a, ui.Offset b){
  final dx = a.dx - b.dx;
  final dy = a.dy - b.dy;
  return dx * dx + dy * dy;
}

// crossProduct product of two points
double crossProduct(ui.Offset a, ui.Offset b){return a.dx * b.dy - a.dy * b.dx;}

// returns the centroid of a list of points by summing their x/y and deviding by num of points
ui.Offset centroid(List<ui.Offset> points){
  double x = 0;
  double y = 0;
  for(final point in points){
    x += point.dx;
    y += point.dy;
  }
  return ui.Offset(x / points.length, y / points.length);
}

// returns closest point
ui.Offset? closestCentroid(ui.Offset point, List<ui.Offset> centroids,){
  ui.Offset? bestPoint;
  double? shortestDistance;
  for(final c in centroids){
    final d2 = distanceSquared(point, c);
    if(shortestDistance == null || d2 < shortestDistance){
      shortestDistance = d2;
      bestPoint = c;
    }
  }
  return bestPoint;
}

class PointCluster {
  double sumX = 0;
  double sumY = 0;
  int count = 0;

  PointCluster(ui.Offset point){
    sumX = point.dx;
    sumY = point.dy;
    count = 1;
  }

  void add(ui.Offset point){
    sumX += point.dx;
    sumY += point.dy;
    count++;
  }

  ui.Offset get centroid {
    return ui.Offset(sumX / count, sumY / count);
  }
}

