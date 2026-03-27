import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import '../util/mapPainter/image_painter.dart';
import '../util/mapPainter/face_painter.dart';
import '../util/mapPainter/edge_painter.dart';
import '../util/faceDetection/face_detection_graph.dart';


// widget for displaying a Map without the ability to edit it
class MapViewer extends StatefulWidget {
  const MapViewer({
    super.key,
    required this.image,
    required this.graph,
    required this.mapName,
    this.showSelectButton = false,
  });

  final ui.Image image;
  final PlanarGraph graph;
  final String mapName;
  final bool showSelectButton;

  @override
  State<MapViewer> createState() => _MapViewerState();
}

class _MapViewerState extends State<MapViewer> {
  // controlls the zoom and positioning of the map
  final TransformationController _transformationController = TransformationController();
  Matrix4 _gestureStartMatrix = Matrix4.identity();
  Offset _gestureStartSceneFocalPoint = Offset.zero;
  bool _viewerInitialised = false;
  // convert a point from the transformed map to actual position
  Offset _toScene(Offset p){
    final inverse = Matrix4.inverted(_transformationController.value);
    return MatrixUtils.transformPoint(inverse, p);
  }
  // initialise values for zoom and positioning control
  void _initialiseViewer(Size viewportSize){
    final imageWidth = widget.image.width.toDouble();
    final imageHeight = widget.image.height.toDouble();
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
  void dispose(){
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mapName),
      ),
      body: LayoutBuilder(
        builder: (context, constraints){
          final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
          if(!_viewerInitialised){
            _initialiseViewer(viewportSize);
            _viewerInitialised = true;
          }

          return Stack(
            children: [
              // Map view
              ClipRect(
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

                    final transformedStartFocal = MatrixUtils.transformPoint(nextMatrix, sceneFocal);
                    final correction = focalNow - transformedStartFocal;
                    // shift if the focal point has changed
                    nextMatrix.translateByDouble(
                      correction.dx,
                      correction.dy,
                      0,
                      1,
                    );

                    _transformationController.value = nextMatrix;

                  },
                  child: SizedBox(
                    width: viewportSize.width,
                    height: viewportSize.height,
                    child: Transform(
                      transform: _transformationController.value,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: widget.image.width.toDouble(),
                          height: widget.image.height.toDouble(),
                          child: Stack(
                            children: [
                              // draws the image
                              CustomPaint(
                                size: Size(widget.image.width.toDouble(), widget.image.height.toDouble()),
                                painter: ImagePainter(widget.image),
                              ),
                              // draws the faces (Zones)
                              CustomPaint(
                                size: Size(widget.image.width.toDouble(), widget.image.height.toDouble()),
                                painter: FacePainter(
                                  faces: widget.graph.faces,
                                  drawLabel: true,
                                ),
                              ),
                              // draws the edges
                              CustomPaint(
                                size: Size(widget.image.width.toDouble(), widget.image.height.toDouble()),
                                painter: EdgePainter(edges: widget.graph.edges),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Select Map button (only shown when used from the lobby)
              if (widget.showSelectButton)
                Positioned(
                  bottom: 24,
                  left: 24,
                  right: 24,
                  child: SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.check),
                      label: const Text('Select Map'),
                      onPressed: () => Navigator.pop(context, true),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}