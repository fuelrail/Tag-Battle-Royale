import 'dart:ui' as ui;
import 'dart:math' as math;

import 'label_position.dart';

import 'face_detection_point.dart';
import 'face_detection_segment.dart';

class GraphBuilder {
  final double mergeTolerance;
  final double epsilon;
  final double minimumFaceArea;
  final PointBuilder pointBuilder;
  final SegmentBuilder segmentBuilder;

  GraphBuilder({
    required this.mergeTolerance,
    required this.minimumFaceArea,
    required this.epsilon,
    required this.pointBuilder,
    required this.segmentBuilder,
  });
  // build the graph and find the faces
  PlanarGraph buildPlanarGraph(List<SegmentData> segments, Map<SegmentRef, List<ui.Offset>> intersections){
    final vertices = <Vertex>[];
    int vid = 0;
    // return vertex for points -> same vertex if close together
    Vertex getVertex(ui.Offset p){
      for(final vertex in vertices){
        if(pointBuilder.samePoint(vertex.p, p)){
          return vertex;
        }
      }
      final vertex = Vertex(vid++, p);
      vertices.add(vertex);
      return vertex;
    }

    final edges = <Edge>[];
    int eid = 0;
    final edgeKeys = <String>{};

    // sort the interections in a segment from start to end
    // add egdes accordingly
    for(final segment in segments){
      final points = <ui.Offset>[segment.a];
      final mids = intersections[segment.ref] ?? const [];
      points.addAll(mids);
      points.add(segment.b);

      final ordered = sortAlongSegment(segment.a, segment.b, pointBuilder.clusterPoints(points));

      for(int i = 0; i < ordered.length - 1; i++){
        final p = ordered[i];
        final q = ordered[i + 1];

        if(distanceSquared(p, q) <= epsilon * epsilon){continue;}

        final vp = getVertex(p);
        final vq = getVertex(q);
        if(vp.id == vq.id) continue;

        final key = edgeKey(vp.id, vq.id);
        if(edgeKeys.contains(key)){continue;}

        edgeKeys.add(key);
        final edge = Edge(eid++, vp, vq);
        edges.add(edge);
        vp.outgoing.add(edge.ab);
        vq.outgoing.add(edge.ba);
      }
    }

    final pruned = pruneGraph(vertices, edges);
    final finalVertices = pruned.vertices;
    final bridgeKeys = findBridgeKeys(finalVertices, pruned.edges);

    final finalEdges = pruned.edges.where((e) => !bridgeKeys.contains(edgeKey(e.a.id, e.b.id))).toList();

    rebuildOutgoing(finalVertices, finalEdges);
    final faces = traceFaces(finalVertices, finalEdges).where((f) => !f.isOuter).toList(); 
    PlanarGraph graph = PlanarGraph(vertices: finalVertices, edges: finalEdges, faces: faces);
    final smallFaces = <Face>[];
    for(final face in faces){
      if(face.signedArea <= minimumFaceArea){smallFaces.add(face);}
    }
    for(final face in smallFaces){
      graph = deleteFace(graph, face);
    }

    return graph;
  }
  // unique id for edges v1 -> v2 and v2 -> v1 return the same key
  String edgeKey(int id1, int id2){
    return id1 < id2 ? '$id1:$id2' : '$id2:$id1';
  }
  // removes deadends in the graph by finding any vertices with only one connection and removing it
  // checks recursivley 
  PlanarGraph pruneGraph(List<Vertex> vertices, List<Edge> edges){
    final remaining = <Edge>{...edges};

    while(true){
      final degree = <Vertex, int>{for(final v in vertices) v: 0};
      for(final edge in remaining){
        degree[edge.a] = (degree[edge.a] ?? 0) + 1;
        degree[edge.b] = (degree[edge.b] ?? 0) + 1;
      }
      final degreeOne = degree.entries.where((entry) => entry.value == 1).map((entry) => entry.key).toSet();
      if(degreeOne.isEmpty){break;}

      remaining.removeWhere((edge) => degreeOne.contains(edge.a) || degreeOne.contains(edge.b));
    }
    final survivingVertices = vertices.where((vertex){
      for(final edge in remaining){
        if(edge.a.id == vertex.id || edge.b.id == vertex.id){
          return true;
        }
      }
      return false;
    }).toList();

    return PlanarGraph(vertices:survivingVertices, edges:remaining.toList(), faces:[]);
  }

  // sorts the vertice edges by angle -> needed to ensure face tracing algortithm
  void rebuildOutgoing(List<Vertex> vertices, List<Edge> edges){
    for(final vertex in vertices){
      vertex.outgoing.clear();
    }

    for(final edge in edges){
      edge.a.outgoing.add(edge.ab);
      edge.b.outgoing.add(edge.ba);
    }

    for(final vertex in vertices){
      vertex.outgoing.sort((a, b) => a.angle.compareTo(b.angle));
    }
  }

  // takes a start and end point and a list of points on a -> b and returns the points sorted along the line a -> b
  List<ui.Offset> sortAlongSegment(ui.Offset a, ui.Offset b,  List<ui.Offset> points){
    final ab = b - a;
    final denom = ab.dx * ab.dx + ab.dy * ab.dy;
    final out = [...points];

    out.sort((p1, p2){
      final t1 = denom <= epsilon ? 0.0 : ((p1.dx - a.dx) * ab.dx + (p1.dy - a.dy) * ab.dy) / denom;
      final t2 = denom <= epsilon ? 0.0 : ((p2.dx - a.dx) * ab.dx + (p2.dy - a.dy) * ab.dy) / denom;
      return t1.compareTo(t2);
    });

    return out;
  }
  // traces faces by always taking a "left" turn
  // if graph is planar then finds all faces
  List<Face> traceFaces(List<Vertex> vertices, List<Edge> edges){
    // collect all half edges from edges a -> b and b -> a
    final allHalfEdges = <HalfEdge>[];
    for(final edge in edges){
      allHalfEdges.add(edge.ab);
      allHalfEdges.add(edge.ba);
    }

    final visited = <int>{};
    final faces = <Face>[];
    int faceCount = 0;
    // for each half edge
    for(final start in allHalfEdges){
      // dont start at edges weve already seen
      if(visited.contains(start.id)) continue;
      final poly = <ui.Offset>[];
      final walked = <HalfEdge>[];
      final localSeen = <int>{};

      HalfEdge current = start;
      bool valid = false;
      while(true){
        // if weve seen it this loop and its the start then valid
        if(localSeen.contains(current.id)){
          if(current.id == start.id){
            valid = true;
          }
          // else get rid of the loop
          break;
        }
        // add the current half edge to whats been seen and store the points
        localSeen.add(current.id);
        walked.add(current);
        poly.add(current.from.p);

        final next = nextFaceEdge(current);
        if(next == null){
          break;
        }
        current = next;
      }

      if(!valid) continue;
      if(poly.length <= 2) continue;
      if(hasRepeatedVertex(poly)) continue;

      // store the edges weve seen
      for(final e in walked){
        visited.add(e.id);
      }

      final area = signedArea(poly);
      //create the face
      faces.add(Face(faceID:0, name:"", polygon: poly, centroid: findPoleOfInaccessibility(poly, pointBuilder), signedArea: area));
    }

    final dedup = <String, Face>{};
    for(final face in faces){
      final key = faceID(face.polygon);
      dedup.putIfAbsent(key, () => face);
    }

    for(final face in dedup.values){
      face.faceID = faceCount;
      face.name = "Zone $faceCount";
      faceCount++;
    }
    return dedup.values.toList();
  }

  // finds any keys that lead to bridges between faces
  // Tarjan's Algorithm
  // https://www.geeksforgeeks.org/dsa/bridge-in-a-graph/
  Set<String> findBridgeKeys(List<Vertex> vertices, List<Edge> edges){
    final adjacency = <int, List<Edge>>{};
    for(final v in vertices){
      adjacency[v.id] = [];
    }

    for(final e in edges){
      adjacency[e.a.id]!.add(e);
      adjacency[e.b.id]!.add(e);
    }

    final disc = <int, int>{};
    final low = <int, int>{};
    final visited = <int>{};
    final bridges = <String>{};

    int time = 0;

    void dfs(int u, Edge? parentEdge){
      visited.add(u);
      disc[u] = time;
      low[u] = time;
      time++;

      for(final edge in adjacency[u]!){
        final v = edge.a.id == u ? edge.b.id : edge.a.id;

        if(parentEdge != null && edge.id == parentEdge.id){
          continue;
        }

        if(!visited.contains(v)){
          dfs(v, edge);

          low[u] = math.min(low[u]!, low[v]!);

          if(low[v]! > disc[u]!){
            bridges.add(edgeKey(edge.a.id, edge.b.id));
          }
        } else {
          low[u] = math.min(low[u]!, disc[v]!);
        }
      }
    }

    for(final v in vertices){
      if(!visited.contains(v.id)){
        dfs(v.id, null);
      }
    }

    return bridges;
  }

  // determines if repeat vertex appears
  bool hasRepeatedVertex(List<ui.Offset> points){
      for(int i = 0; i < points.length; i++){
        for(int j = i + 1; j < points.length; j++){
          if(pointBuilder.samePoint(points[i], points[j])){
            return true;
          }
        }
      }
      return false;
    }

  // determines the next edge to go to. Find the edges twin in the two vertice and takes one step counterclockwise
  HalfEdge? nextFaceEdge(HalfEdge current){
  final vertex = current.to.outgoing;
  if(vertex.isEmpty){return null;}

  final twin = current.twin;
  final index = vertex.indexWhere((e) => e.id == twin.id);
  if(index == -1) return null;

  final n = vertex.length;
  if(n == 1) return null;

  final nextIndex = (index - 1 + n) % n;
  final next = vertex[nextIndex];

  if(next.id == twin.id) return null;
  return next;
  }
  // takes the points for a face and returns a unique id, vertex order independent
  String faceID(List<ui.Offset> poly){
    final points = poly.map((p) => pointBuilder.pointKey(p, mergeTolerance / 2)).toList();

    int best = 0;
    for(int i = 1; i < points.length; i++){
      if(points[i].compareTo(points[best]) < 0){best = i;}
    }

    final rotated = <String>[];
    for(int i = 0; i < points.length; i++){
      rotated.add(points[(best + i) % points.length]);
    }

    final reversed = rotated.reversed.toList();
    final a = rotated.join('|');
    final b = reversed.join('|');
    return a.compareTo(b) <= 0 ? a : b;
  }
  // takes a list of points and returns the signed areas defined by those points e.g. a sqaure could be 4 or -4
  double signedArea(List<ui.Offset> poly){
    if(poly.length < 3) return 0;
    double area = 0;
    for(int i = 0; i < poly.length; i++){
      final p = poly[i];
      final q = poly[(i + 1) % poly.length];
      area += p.dx * q.dy - q.dx * p.dy;
    }
    return area / 2.0;
  }

  // removes the longest edge for a face and rebuilds the graph
  PlanarGraph deleteFace(PlanarGraph graph, Face face){
    final targetFaceEdgeKeys = faceEdgeKeys(graph, face);
    final edgeUseCount = <String, int>{};
    for(final f in graph.faces){
      final keys = faceEdgeKeys(graph, f);
      for(final key in keys){
        edgeUseCount[key] = (edgeUseCount[key] ?? 0) + 1;
      }
    }

    final sharedInternalKeys = targetFaceEdgeKeys.where((key){
      return (edgeUseCount[key] ?? 0) > 1;
    }).toSet();

    List<Edge> keptEdges;
    
    // no shared boundary, so just delete this face's own edges
  if(sharedInternalKeys.isEmpty){
      keptEdges = graph.edges.where((e){
        final key = edgeKey(e.a.id, e.b.id);
        return !targetFaceEdgeKeys.contains(key);
      }).toList();
    } else {

      final used = <int>{};
      List<Edge>? bestChain;
      double bestScore = double.infinity;

      for(final edge in graph.edges){
        if(used.contains(edge.id)) continue;

        final chain = collectEdgeChain(edge, graph, used);
        // check if this chain is part of the face AND is internal
        bool isCandidate = false;
        for(final e in chain){
          final key = edgeKey(e.a.id, e.b.id);
          if(sharedInternalKeys.contains(key)){
            isCandidate = true;
            break;
          }
        }

        if(!isCandidate) continue;
        // score = distance of chain midpoint to face centroid
        double avgX = 0;
        double avgY = 0;
        int count = 0;

        for(final e in chain){
          avgX += e.a.p.dx + e.b.p.dx;
          avgY += e.a.p.dy + e.b.p.dy;
          count += 2;
        }
        avgX /= count;
        avgY /= count;
        final dx = avgX - face.centroid.dx;
        final dy = avgY - face.centroid.dy;
        final distSq = dx * dx + dy * dy;

        if(distSq < bestScore){
          bestScore = distSq;
          bestChain = chain;
        }
      }

      if(bestChain == null) return graph;
      final removeIds = bestChain.map((e) => e.id).toSet();
      keptEdges = graph.edges.where((e){
        return !removeIds.contains(e.id);
      }).toList();
    }

    final pruned = pruneGraph(graph.vertices, keptEdges);
    final finalVertices = pruned.vertices;
    final finalEdges = pruned.edges;
    rebuildOutgoing(finalVertices, finalEdges);
    final faces = traceFaces(finalVertices, finalEdges).where((f) => !f.isOuter).toList();
    return PlanarGraph(vertices: finalVertices, edges: finalEdges, faces: faces);
  }

  //used to treat a collection of vertices with degree 2 as the same edge
  List<Edge> collectEdgeChain(Edge start, PlanarGraph graph, Set<int> used){
    final chain = <Edge>[];
    chain.add(start);
    used.add(start.id);

    int degree(Vertex v) => v.outgoing.length;

    // forward
    Vertex prev = start.a;
    Vertex current = start.b;

    while(degree(current) == 2){
      final nextHalf = current.outgoing.firstWhere(
        (h) => h.to.id != prev.id,
      );
      final nextEdge = nextHalf.edge;
      if(used.contains(nextEdge.id)) break;
      chain.add(nextEdge);
      used.add(nextEdge.id);
      prev = current;
      current = nextHalf.to;
    }

    // backward
    prev = start.b;
    current = start.a;
    while(degree(current) == 2){
      final nextHalf = current.outgoing.firstWhere(
        (h) => h.to.id != prev.id,
      );
      final nextEdge = nextHalf.edge;
      if(used.contains(nextEdge.id)) break;
      chain.insert(0, nextEdge);
      used.add(nextEdge.id);
      prev = current;
      current = nextHalf.to;
    }

    return chain;
  }
  // finds the keys for the edges in a face
  Set<String> faceEdgeKeys(PlanarGraph graph, Face face){
    final keys = <String>{};
    for(int i = 0; i < face.polygon.length; i++){
      final p = face.polygon[i];
      final q = face.polygon[(i + 1) % face.polygon.length];

      Vertex? vp;
      Vertex? vq;
      for(final v in graph.vertices){
        if(vp == null && pointBuilder.samePoint(v.p, p)){
          vp = v;
        }
        if(vq == null && pointBuilder.samePoint(v.p, q)){
          vq = v;
        }
        if(vp != null && vq != null) break;
      }

      if(vp != null && vq != null){
        keys.add(edgeKey(vp.id, vq.id));
      }
    }
    return keys;
  }
}

class Face {
  int faceID;
  String name;
  final List<ui.Offset> polygon;
  final double signedArea;
  final ui.Offset centroid;

  Face({
    required this.name,
    required this.faceID,
    required this.centroid,
    required this.polygon,
    required this.signedArea,
  });

  bool get isOuter => signedArea < 0;

  Map<String, dynamic> toJson(){
    return {
      'faceID': faceID,
      'name': name,
      'polygon': polygon.map(_offsetToJson).toList(),
      'signedArea': signedArea,
      'centroid': _offsetToJson(centroid),
    };
  }

  factory Face.fromJson(Map<String, dynamic> json){
    return Face(
      name: json['name'] as String,
      faceID: json['faceID'] as int,
      centroid: _offsetFromJson(json['centroid'] as Map<String, dynamic>),
      polygon: (json['polygon'] as List)
          .map((p) => _offsetFromJson(p as Map<String, dynamic>))
          .toList(),
      signedArea: (json['signedArea'] as num).toDouble(),
    );
  }

  @override
  String toString() =>
      'Face(area=${signedArea.toStringAsFixed(2)}, verts=${polygon.length})';

  @override
  bool operator ==(Object other){
    if(identical(this, other)) return true;
    return other is Face && other.faceID == faceID;
  }

  @override
  int get hashCode => faceID.hashCode;
}

class PlanarGraph {
  final List<Vertex> vertices;
  final List<Edge> edges;
  final List<Face> faces;

  PlanarGraph({
    required this.vertices,
    required this.edges,
    required this.faces,
  });
  // detects if a point p is in a face of this graph and returns that face if true
  Face? pointInFace(ui.Offset p){
    Face? best;
    double? bestAbsArea;
    for(final face in faces){
      bool inside = false;
      int i = 0;
      while(i < face.polygon.length){

        final a = face.polygon[i % face.polygon.length];
        final b = face.polygon[(i + 1) % face.polygon.length];
        // one point above and one point below AND if p is on the left of a -> b
        final intersects = ((a.dy > p.dy) != (b.dy > p.dy)) && (p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx);
        // inside if odd number of intersections
        if(intersects){inside = !inside;}
        i++;
      }
      if(inside){
        final area = face.signedArea.abs();
        if(best == null || area < bestAbsArea!){
          best = face;
          bestAbsArea = area;
        }
      }
    }
    return best;
  }

  Map<String, dynamic> toJson(){
    return {
      'vertices': vertices.map((v) => v.toJson()).toList(),
      'edges': edges.map((e) => e.toJson()).toList(),
      'faces': faces.map((f) => f.toJson()).toList(),
    };
  }

  factory PlanarGraph.fromJson(Map<String, dynamic> json){
    final vertices = (json['vertices'] as List)
        .map((v) => Vertex.fromJson(v as Map<String, dynamic>))
        .toList();

    final vertexById = {for(final v in vertices) v.id: v};

    final edges = (json['edges'] as List)
        .map((e) => Edge.fromJson(e as Map<String, dynamic>, vertexById))
        .toList();

    final faces = (json['faces'] as List)
        .map((f) => Face.fromJson(f as Map<String, dynamic>))
        .toList();

    return PlanarGraph(
      vertices: vertices,
      edges: edges,
      faces: faces,
    );
  }
}

class Vertex {
  final int id;
  final ui.Offset p;
  final List<HalfEdge> outgoing = [];

  Vertex(this.id, this.p);

  Map<String, dynamic> toJson(){
    return {
      'id': id,
      'p': _offsetToJson(p),
    };
  }

  factory Vertex.fromJson(Map<String, dynamic> json){
    return Vertex(
      json['id'] as int,
      _offsetFromJson(json['p'] as Map<String, dynamic>),
    );
  }

  @override
  String toString() => 'V$id(${p.dx.toStringAsFixed(1)}, ${p.dy.toStringAsFixed(1)})';
}

class Edge {
  final int id;
  final Vertex a;
  final Vertex b;
  late final HalfEdge ab;
  late final HalfEdge ba;

  Edge(this.id, this.a, this.b){
    ab = HalfEdge(id * 2, a, b, this);
    ba = HalfEdge(id * 2 + 1, b, a, this);
    ab.twin = ba;
    ba.twin = ab;
  }

  Map<String, dynamic> toJson(){
    return {
      'id': id,
      'a': a.id,
      'b': b.id,
    };
  }

  factory Edge.fromJson(
    Map<String, dynamic> json,
    Map<int, Vertex> vertexById,
  ){
    return Edge(
      json['id'] as int,
      vertexById[json['a'] as int]!,
      vertexById[json['b'] as int]!,
    );
  }
}

class HalfEdge {
  final int id;
  final Vertex from;
  final Vertex to;
  final Edge edge;
  late HalfEdge twin;

  HalfEdge(this.id, this.from, this.to, this.edge);

  double get angle => math.atan2(to.p.dy - from.p.dy, to.p.dx - from.p.dx);
}

Map<String, dynamic> _offsetToJson(ui.Offset p){
  return {
    'x': p.dx,
    'y': p.dy,
  };
}

ui.Offset _offsetFromJson(Map<String, dynamic> json){
  return ui.Offset(
    (json['x'] as num).toDouble(),
    (json['y'] as num).toDouble(),
  );
}