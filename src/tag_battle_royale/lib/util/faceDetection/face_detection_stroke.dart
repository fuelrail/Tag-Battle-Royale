import 'dart:math' as math;
import 'dart:ui' as ui;

import '../stroke.dart';
import 'face_detection_point.dart';

class StrokeBuilder {
  final double snapTolerance;
  final double simplifyTolerance;
  final double epsilon;
  final PointBuilder pointBuilder;

  StrokeBuilder({
    required this.snapTolerance,
    required this.simplifyTolerance,
    required this.epsilon,
    required this.pointBuilder
  });

  List<Stroke> prepareStrokes(List<Stroke> input){
    final simplified = <Stroke>[];

    for(final s in input){
      var points = s.points.map((p) => ui.Offset(p.dx, p.dy)).toList();
      points = simplifyPoints(points);
      points = simplifyColinearPoints(points, 0.98);
      points = rdpSimplify(points);
      points = simplifyPoints(points);

      if(points.length >= 2){
        simplified.add(
          Stroke(
            index: s.index,
            points: points,
            width: s.width,
            color: s.color,
          ),
        );
      }
    }
    snapNearbyEndpoints(simplified);
    return simplified;
  }

  // removes points within a tolerance and snaps final point to the start if within certain tolerance
  List<ui.Offset> simplifyPoints(List<ui.Offset> points){
    if(points.isEmpty) return points;

    final out = <ui.Offset>[points.first];
    for(int i = 1; i < points.length; i++){
      if(!pointBuilder.samePoint(out.last, points[i], simplifyTolerance)){
        out.add(points[i]);
      }
    }
    if(out.length > 2 && pointBuilder.samePoint(out.first, out.last, simplifyTolerance)){
      out[out.length - 1] = out.first;
    }
    return out;
  }

  // reduces point count by removing colinear points (mid point on a straight line) 
  List<ui.Offset> simplifyColinearPoints(List<ui.Offset> points, double tol){
    if(points.length <= 2) return points;

    final out = <ui.Offset>[points.first];
    for(int i = 1; i < points.length - 1; i++){
      final a = out.last;
      final b = points[i];
      final c = points[i + 1];

      final len1 = math.sqrt(distanceSquared(a, b));
      final len2 = math.sqrt(distanceSquared(b, c));

      if(len1 <= epsilon || len2 <= epsilon){
        out.add(b);
        continue;
      }
      // angle between two lines
      final dir1 = b - a;
      final dir2 = c - b;
      final dot = (dir1.dx * dir2.dx + dir1.dy * dir2.dy) / (len1 * len2);
      final nearlyStraight = dot > tol;

      final dist = pointBuilder.pointLineDistance(b, a, c);
      if(!(dist <= simplifyTolerance && nearlyStraight)){
        out.add(b);
      }
    }

    out.add(points.last);
    return out;
  }

  // Ramer–Douglas–Peucker algorithm to simplify polyline
  // find furthest point from line start -> end if in tolerance then remove all points inbetween start and end
  // else keep point and perform start -> point and point -> end 
  List<ui.Offset> rdpSimplify(List<ui.Offset> points){
    if(points.length <= 2) return points;

    final keepPoint = List<bool>.filled(points.length, false);
    keepPoint[0] = true;
    keepPoint[points.length - 1] = true;

    void recurse(int start, int end){
      if(end <= start + 1) return;

      double maxDistance = -1;
      int index = -1;
      for(int i = start + 1; i < end; i++){
        final distance = pointBuilder.pointLineDistance(points[i], points[start], points[end]);
        if(distance > maxDistance){
          maxDistance = distance;
          index = i;
        }
      }
      if(maxDistance > simplifyTolerance && index != -1){
        keepPoint[index] = true;
        recurse(start, index);
        recurse(index, end);
      }
    }

    recurse(0, points.length - 1);
    final out = <ui.Offset>[];
    for(int i = 0; i < points.length; i++){
      if(keepPoint[i]){out.add(points[i]);}
    }
    return out;
  }

  // addeds a connection between endpoints if within tolerance
  void snapNearbyEndpoints(List<Stroke> strokes){
    final endpoints = <StrokeEndpoint>[];

    for(final stroke in strokes){
      if(stroke.points.length < 2) continue;
      endpoints.add(StrokeEndpoint(stroke, 0));
      endpoints.add(StrokeEndpoint(stroke, stroke.points.length - 1));
    }

    final snappedPoints = pointBuilder.clusterPoints(endpoints.map((e) => e.point).toList(), snapTolerance);

    for(final endpoint in endpoints){
      for(final snapped in snappedPoints){
        if(pointBuilder.samePoint(endpoint.point, snapped, snapTolerance)){
          endpoint.stroke.points[endpoint.pointIndex] = snapped;
          break;
        }
      }
    }
  }
}

class StrokeEndpoint {
  final Stroke stroke;
  final int pointIndex;

  StrokeEndpoint(this.stroke, this.pointIndex);

  ui.Offset get point{return stroke.points[pointIndex];}
}