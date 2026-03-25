import 'dart:math' as math;
import 'dart:ui' as ui;

import '../stroke.dart';
import 'face_detection_point.dart';

class SegmentBuilder {
  final double cellSize;
  final double mergeTolerance;
  final double endpointToSegmentTolerance;
  final double epsilon;
  final PointBuilder pointBuilder;

  SegmentBuilder({
    required this.cellSize,
    required this.mergeTolerance,
    required this.endpointToSegmentTolerance,
    required this.epsilon,
    required this.pointBuilder,
  });

  // creates segments from strokes e.g. p1 p2 p3 -> seg1 seg2
  List<SegmentData> buildSegments(List<Stroke> strokes){
    final out = <SegmentData>[];
    for(final stroke in strokes){
      for(int i = 0; i < stroke.points.length - 1; i++){
        final a = stroke.points[i];
        final b = stroke.points[i + 1];
        if(distanceSquared(a, b) <= epsilon * epsilon) continue;

        out.add(
          SegmentData(
            ref: SegmentRef(stroke.index, i),
            a: a,
            b: b,
          ),
        );
      }
    }
    return out;
  }

  // finds the intersection between p1 -> p2 and q1 -> q2
  // https://stackoverflow.com/questions/563198/how-do-you-detect-where-two-line-segments-intersect
  // ^ was very helpful
  ui.Offset? segmentIntersection(ui.Offset p1, ui.Offset p2, ui.Offset q1, ui.Offset q2){
    final r = p2 - p1;
    final s = q2 - q1;
    final rxs = crossProduct(r, s);
    final qp = q1 - p1;
    final qpxr = crossProduct(qp, r);
    // lines are collinear and parallel
    if(rxs.abs() < epsilon && qpxr.abs() < epsilon){
      return null;
    }
    // lines are parallel
    if(rxs.abs() < epsilon){
      return null;
    }
    final t = crossProduct(qp, s) / rxs;
    final u = crossProduct(qp, r) / rxs;
    //is the hit on the line p or q
    final onP = t >= -epsilon && t <= 1.0 + epsilon;
    final onQ = u >= -epsilon && u <= 1.0 + epsilon;
    if(!onP || !onQ) return null;

    final hit = ui.Offset(p1.dx + t * r.dx, p1.dy + t * r.dy);
    final isP1 = pointBuilder.samePoint(hit, p1);
    final isP2 = pointBuilder.samePoint(hit, p2);
    final isQ1 = pointBuilder.samePoint(hit, q1);
    final isQ2 = pointBuilder.samePoint(hit, q2);
    // return the point if on at most 1 endpoint
    final endpointCount = (isP1 ? 1 : 0) + (isP2 ? 1 : 0) + (isQ1 ? 1 : 0) + (isQ2 ? 1 : 0);
    if(endpointCount <= 1){
      return hit;
    }
    return null;
  }
  // projects p onto a -> b and returns the point if it lies on a -> b
  ui.Offset? projectPointOnSegment(ui.Offset p, ui.Offset a, ui.Offset b){
    final ab = b - a;
    final denom = ab.dx * ab.dx + ab.dy * ab.dy;
    if(denom <= epsilon) return null;

    final t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / denom;
    if(t < 0.0 || t > 1.0) return null;

    return ui.Offset(a.dx + t * ab.dx, a.dy + t * ab.dy);
  }

  // push p to list if p is unique
  void pushUnique(List<ui.Offset> list, ui.Offset point){
    for(final q in list){
      if(pointBuilder.samePoint(point, q)) return;
    }
    list.add(point);
  }

  // find the intersections
  Map<SegmentRef, List<ui.Offset>> findIntersections(List<SegmentData> segments){
    // find where segments intersect
    // map from segment to interections
    final segmentPoints = <SegmentRef, List<ui.Offset>>{};
    for(final segment in segments){
      segmentPoints[segment.ref] = [];
    }
    // spaitial hash so only nearby segments are checked against eachother for intersections
    final spaitialHash = <String, List<int>>{};
    for(int i = 0; i < segments.length; i++){
      for(final key in cellKeys(segments[i].a, segments[i].b)){
        spaitialHash.putIfAbsent(key, () => []).add(i);
      }
    }
    // for each segment
    for(int i = 0; i < segments.length; i++){
      final seg = segments[i];
      final candidates = <int>{};
      // find the candidates to be checked
      for(final key in cellKeys(seg.a, seg.b)){
        final ids = spaitialHash[key];
        if(ids != null) candidates.addAll(ids);
      }
      // for each candidate
      for(final j in candidates){
        if(i >= j) continue;
        final other = segments[j];
        final hit = segmentIntersection(seg.a, seg.b, other.a, other.b);
        // if theres an intersection store it
        if(hit != null){
          pushUnique(segmentPoints[seg.ref]!, hit);
          pushUnique(segmentPoints[other.ref]!, hit);
        }
      }
    }
    // find where endpoints intersect segments
    final endpoints = <EndpointRef>[];
    int i = 0;
    while( i < segments.length){
      if(segments[i].ref.segmentIndex == 0){
        endpoints.add(EndpointRef(segments[i].ref, segments[i].a));
      }else if(i == segments.length - 1 || segments[i + 1].ref.strokeIndex != segments[i].ref.strokeIndex){
        endpoints.add(EndpointRef(segments[i].ref, segments[i].b));
      }
      i++;
    }
    // for each endpoint
    for(final ep in endpoints){
      SegmentData? bestSeg;
      ui.Offset? bestProj;
      double bestDistance = double.infinity;
      // for each segment
      for(final seg in segments){
        if(seg.ref == ep.segmentRef){continue;}
        if(pointBuilder.samePoint(ep.point, seg.a) || pointBuilder.samePoint(ep.point, seg.b)){continue;}

        final proj = projectPointOnSegment(ep.point, seg.a, seg.b);
        if(proj == null){continue;}

        final distSquared = distanceSquared(ep.point, proj);
        if(distSquared > endpointToSegmentTolerance * endpointToSegmentTolerance){continue;}
        if(pointBuilder.samePoint(proj, seg.a) || pointBuilder.samePoint(proj, seg.b)){continue;}

        // find the closest segment
        if(distSquared < bestDistance){
          bestDistance = distSquared;
          bestSeg = seg;
          bestProj = proj;
        }
      }
      if(bestSeg != null && bestProj != null){
        pushUnique(segmentPoints[ep.segmentRef]!, bestProj);
        pushUnique(segmentPoints[bestSeg.ref]!, bestProj);
      }
    }

    final finalPoints = <ui.Offset>[];
    for(final points in segmentPoints.values){
      finalPoints.addAll(points);
    }
    // remap the points to the clustered locations
    final merged = pointBuilder.clusterPoints(finalPoints);
    final remappedPoints = <SegmentRef, List<ui.Offset>>{};

    for(final entry in segmentPoints.entries){
      final out = <ui.Offset>[];
      for(final p in entry.value){
        final snapped = closestCentroid(p, merged);
        if(snapped != null){
          pushUnique(out, snapped);
        }
      }
      remappedPoints[entry.key] = out;
    }
    return remappedPoints;
  }
  // returns the cells for which a -> b should be checked
  List<String> cellKeys(ui.Offset a, ui.Offset b){
    final minX = math.min(a.dx, b.dx);
    final maxX = math.max(a.dx, b.dx);
    final minY = math.min(a.dy, b.dy);
    final maxY = math.max(a.dy, b.dy);

    final x0 = (minX / cellSize).floor();
    final x1 = (maxX / cellSize).floor();
    final y0 = (minY / cellSize).floor();
    final y1 = (maxY / cellSize).floor();

    final out = <String>[];
    for(int x = x0; x <= x1; x++){
      for(int y = y0; y <= y1; y++){
        out.add('$x:$y');
      }
    }
    return out;
  }
}

class EndpointRef {
  final SegmentRef segmentRef;
  final ui.Offset point;
  EndpointRef(this.segmentRef, this.point);
}

class SegmentRef {
  final int strokeIndex;
  final int segmentIndex;

  const SegmentRef(this.strokeIndex, this.segmentIndex);

  @override
  bool operator ==(Object other) =>
      other is SegmentRef &&
      other.strokeIndex == strokeIndex &&
      other.segmentIndex == segmentIndex;

  @override
  int get hashCode => Object.hash(strokeIndex, segmentIndex);

  @override
  String toString() => '($strokeIndex,$segmentIndex)';
}

class SegmentData {
  final SegmentRef ref;
  final ui.Offset a;
  final ui.Offset b;

  const SegmentData({
    required this.ref,
    required this.a,
    required this.b,
  });
}
