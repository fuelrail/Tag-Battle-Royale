import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:async';

import '../util/map_file_handler.dart';
import '../util/mapPainter/image_painter.dart';
import '../util/mapPainter/face_painter.dart';
import '../util/mapPainter/edge_painter.dart';
import '../util/mapPainter/user_painter.dart';
import '../util/mapPainter/current_zone_painter.dart';
import '../util/faceDetection/face_detection_graph.dart';
import '../util/gps.dart';

import 'package:geolocator/geolocator.dart';


// widget for displaying a Map without the ability to edit it
class MapViewer extends StatefulWidget {
  const MapViewer({
    super.key,
    required this.map,
    this.playing = false
  });

  final bool playing;
  final MapFile map;

  @override
  State<MapViewer> createState() => _MapViewerState();
}

class _MapViewerState extends State<MapViewer> {
  ui.Image? image;
  Timer? _locationTimer;
  Position? _currentPosition;
  final int updatesPerSecond = 1;
  // controlls the zoom and positioning of the map
  final TransformationController _transformationController = TransformationController();
  Matrix4 _gestureStartMatrix = Matrix4.identity();
  Offset _gestureStartSceneFocalPoint = Offset.zero;
  bool _viewerInitialised = false;
  Face? _currentZone;

  @override
  void initState() {
    super.initState();
    _loadImage();
    if (widget.playing) {
      _startLocationUpdates();
    }
  }

  void _startLocationUpdates() {
    _locationTimer = Timer.periodic(Duration(milliseconds: (1000 / updatesPerSecond).toInt()), (_) async {
      try {
        final pos = await getLocation();
        final zone = widget.map.graph.pointInFace(_latLngToImage(pos));
        if (mounted) {
          setState(() {
            _currentPosition = pos;
            if(zone != null){_currentZone = zone;}
          });
        }
      } catch (_) {}
    });
  }


  // convert a point from the transformed map to actual position
  Offset _toScene(Offset p){
    final inverse = Matrix4.inverted(_transformationController.value);
    return MatrixUtils.transformPoint(inverse, p);
  }
  Future<void> _loadImage() async {
    final img = await widget.map.getImage();
    if (!mounted) return;
    setState(() {
      image = img;
    });
  }
  // initialise values for zoom and positioning control
  void _initialiseViewer(Size viewportSize){
    final imageWidth = image!.width.toDouble();
    final imageHeight = image!.height.toDouble();
    // scale both x and y to which ever is smaller
    final scaleX = viewportSize.width / imageWidth;
    final scaleY = viewportSize.height / imageHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final fittedWidth = imageWidth * scale;
    final fittedHeight = imageHeight * scale;

    final dx = (viewportSize.width - fittedWidth) / 2;
    final dy = (viewportSize.height - fittedHeight) / 2;

    _transformationController.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }
  // remove when done
  @override
void dispose() {
  _locationTimer?.cancel();
  _transformationController.dispose();
  super.dispose();
}

  Offset _latLngToImage(Position pos) {
    final bounds = widget.map.imageBounds;

    final lat = pos.latitude;
    final lng = pos.longitude;

    final south = bounds.southwest.latitude;
    final west = bounds.southwest.longitude;
    final north = bounds.northeast.latitude;
    final east = bounds.northeast.longitude;

    final x = (lng - west) / (east - west);
    final y = (north - lat) / (north - south);

    return Offset(
      x * image!.width,
      y * image!.height,
    );
  }

  @override
  Widget build(BuildContext context){
    if(image == null){
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.map.mapName),
      ),
      body: LayoutBuilder(
        builder: (context, constraints){
          final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
          if(!_viewerInitialised){
            _initialiseViewer(viewportSize);
            _viewerInitialised = true;
          }

          return ClipRect(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (details){
                // first input we get the inital values 
                _gestureStartMatrix = _transformationController.value.clone();
                _gestureStartSceneFocalPoint = _toScene(details.localFocalPoint);
              },
              onScaleUpdate: (details){
                // each update we change the matrix appropriately
                final focalNow = details.localFocalPoint;
                final sceneFocal = _gestureStartSceneFocalPoint;
                // scale around the focal point
                final nextMatrix = _gestureStartMatrix.clone()
                  ..translateByDouble(sceneFocal.dx, sceneFocal.dy, 0, 1)
                  ..scaleByDouble(details.scale, details.scale, 1, 1)
                  ..translateByDouble(-sceneFocal.dx, -sceneFocal.dy, 0, 1);

                final transformedStartFocal =MatrixUtils.transformPoint(nextMatrix, sceneFocal);
                final correction = focalNow - transformedStartFocal;
                // shift if the focal point has changed
                nextMatrix.translateByDouble(
                  correction.dx,
                  correction.dy,
                  0,
                  1,
                );

                setState(() {
                  _transformationController.value = nextMatrix;
                });

              },
              child: SizedBox(
                width: viewportSize.width,
                height: viewportSize.height,
                child: Transform(
                  transform: _transformationController.value,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: image!.width.toDouble(),
                      height: image!.height.toDouble(),
                      child: Stack(
                        children: [
                          // draws the image
                          CustomPaint(
                            size: Size(image!.width.toDouble(), image!.height.toDouble()),
                            painter: ImagePainter(image!),
                          ),
                          // draws the faces (Zones)
                          CustomPaint(
                            size: Size(image!.width.toDouble(), image!.height.toDouble()),
                            painter: FacePainter(
                              faces: widget.map.graph.faces,
                              drawLabel: true,
                            ),
                          ),
                          // draws the edges
                          CustomPaint(
                            size: Size(image!.width.toDouble(), image!.height.toDouble()),
                            painter: EdgePainter(edges: widget.map.graph.edges),
                          ),
                          CustomPaint(
                            size: Size(image!.width.toDouble(), image!.height.toDouble()),
                            painter: CurrentZonePainter(face: _currentZone),
                          ),
                          if (widget.playing && _currentPosition != null)
                            CustomPaint(
                              size: Size(
                                image!.width.toDouble(),
                                image!.height.toDouble(),
                              ),
                              painter: UserPainter(
                                position: _latLngToImage(_currentPosition!),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}