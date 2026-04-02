import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:ui' as ui;

import '../util/stroke.dart';
import '../util/mapPainter/stroke_painter.dart';
import '../util/mapPainter/image_painter.dart';
import '../util/faceDetection/face_detector.dart';
import '../util/faceDetection/face_detection_graph.dart';
import '../util/mapPainter/face_painter.dart';
import '../util/mapPainter/edge_painter.dart';
import '../util/map_file_handler.dart';

class ImageEditor extends StatefulWidget {
  const ImageEditor({super.key, required this.image, required this.imageBounds});
  final ui.Image image;
  final LatLngBounds imageBounds;

  @override
  ImageEditorState createState() => ImageEditorState();
}

class ImageEditorState extends State<ImageEditor> {
  final List<Stroke> strokes = [
    
  ];
  final List<Stroke> redoStrokes = [];
  
  bool drawMode = true;
  bool drawToggle = false;
  String mapName = "Unnamed Map";

  FaceDetector faceDetector = FaceDetector();

  final TransformationController _transformationController = TransformationController();
  Matrix4 _gestureStartMatrix = Matrix4.identity();
  Offset _gestureStartSceneFocalPoint = Offset.zero;
  bool _viewerInitialised = false;
  @override
  void initState(){
    super.initState();
    int i = 0;
    while(i < strokes.length){
      faceDetector.addStroke(strokes[i]);
      i++;
    }
    faceDetector.buildGraphAndFindFaces();
  }
  // adds a removed stroke bad to strokes
  void _redo(){
    if(redoStrokes.isNotEmpty){
      setState((){
        final stroke = redoStrokes.removeLast();
        strokes.add(stroke);
        faceDetector.addStroke(stroke);
        faceDetector.buildGraphAndFindFaces();
      });
    }
  }
  // removes a stroke and adds it to redoStrokes
  void _undo(){
    if(strokes.isNotEmpty){
      setState((){
        final removed = strokes.removeLast();
        redoStrokes.add(removed);
        faceDetector.removeStroke();
        faceDetector.buildGraphAndFindFaces();
      });
    }
  }
  // toogles draw mode to allow drawing
  void _togglePen(){
    if(!drawMode) return;
    setState(() => drawToggle = !drawToggle);
  }
  // moves to the naming phase
  void _finishDrawMode(){
    setState((){
      drawMode = false;
      drawToggle = false;
    });
  }
  // bad to the draw mode
  void _backToDrawMode(){
    setState((){
      drawMode = true;
    });
  }
  // adds a stroke to strokes and builds graph
  void _finishStroke(){
    if(strokes.isEmpty) return;
    setState((){
      final stroke = strokes.last;
      faceDetector.addStroke(stroke);
      faceDetector.buildGraphAndFindFaces();
    });
  }

  // converts a point from the transformed map to if it were in the starting position
  Offset _toScene(Offset p){
    final inverse = Matrix4.inverted(_transformationController.value);
    return MatrixUtils.transformPoint(inverse, p);
  }
  // returns if a point is within the Map image
  bool _inBounds(Offset p){
    return p.dx >= 0 && p.dy >= 0 && p.dx <= widget.image.width.toDouble() && p.dy <= widget.image.height.toDouble();
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
  // dialogue to edit a face
  void _editFace(Face face){
    final controller = TextEditingController(text: face.name);
    showDialog(
      context: context,
      builder: (context){
        return AlertDialog(
          title: const Text("Edit Face"), 
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: "Name",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => setState((){
                faceDetector.deleteFace(face);
                Navigator.pop(context);
              }),
              child: const Text("Delete"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: (){
                setState((){
                  face.name = controller.text;
                });
                Navigator.pop(context);
              },
              child: const Text("Save"),
            ),
          ],
          
        );
      },
    );
  }

  // dialogue to edit Map Name
  void _editMapName(){
    final controller = TextEditingController(text: mapName);
    showDialog(
      context: context,
      builder: (context){
        return AlertDialog(
          title: const Text("Map Name"),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: "Enter name",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: (){
                setState((){
                  mapName = controller.text.isEmpty
                      ? "Unnamed Map"
                      : controller.text;
                });
                Navigator.pop(context);
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }
  // save the map as a json file
  Future<void> _saveMap() async {
    try {
      final mapFile = await MapFile.create(
        name: mapName,
        image: widget.image,
        imageBounds: widget.imageBounds,
        graph: faceDetector.graph!,
      );

      await mapFile.saveMapFile();

      if(!mounted) return;

      Navigator.pop(context, true);
    } catch (e){
      if(!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Failed to save map"),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _editMapName,
          child: Text(mapName),
        ),
        leading: drawMode ? null : 
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _backToDrawMode,
        ),
        actions: [
          if(drawMode) ...[
            IconButton(
              isSelected: drawToggle,
              icon: const Icon(Icons.draw_outlined),
              selectedIcon: const Icon(Icons.draw),
              onPressed: _togglePen,
            ),
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: _undo,
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              onPressed: _redo,
            ),
          ],
        ],
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: drawMode ? _finishDrawMode : _saveMap,
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),),
            child: Text(drawMode ? "Finished Drawing!" : "Save the Map!"),
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints){
          final viewportSize = Size(
            constraints.maxWidth,
            constraints.maxHeight,
          );

          if(!_viewerInitialised){
            _initialiseViewer(viewportSize);
            _viewerInitialised = true;
          }

          return ClipRect(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // on tap find which face contains the tap and open edit face dialogue
              onTapUp: (details){
                if(drawMode) return;

                final graph = faceDetector.graph;
                if(graph == null) return;

                final p = _toScene(details.localPosition);
                final face = graph.pointInFace(p);
                if(face == null) return;

                _editFace(face);
              },
              // get inital values for transform or start stroke
              onScaleStart: (details){
                _gestureStartMatrix = _transformationController.value.clone();
                _gestureStartSceneFocalPoint = _toScene(details.localFocalPoint);

                if(drawMode && drawToggle && details.pointerCount == 1){
                  final p = _toScene(details.localFocalPoint);
                  if(!_inBounds(p)) return;

                  setState((){
                    strokes.add(Stroke(points: [p], index: strokes.length));
                  });
                }
              },
              // update matrix relative to initial finger position or add stroke
              onScaleUpdate: (details){
                if(drawMode && drawToggle && details.pointerCount == 1){
                  final p = _toScene(details.localFocalPoint);
                  if(!_inBounds(p)) return;
                  if(strokes.isEmpty) return;

                  setState((){
                    strokes.last.add(p);
                  });
                  return;
                }

                if(details.pointerCount >= 2 || !drawMode || !drawToggle){
                  final focalNow = details.localFocalPoint;
                  final sceneFocal = _gestureStartSceneFocalPoint;

                  final nextMatrix = _gestureStartMatrix.clone()
                    ..translateByDouble(sceneFocal.dx, sceneFocal.dy, 0, 1)
                    ..scaleByDouble(details.scale, details.scale, 1, 1)
                    ..translateByDouble(-sceneFocal.dx, -sceneFocal.dy, 0, 1);

                  final transformedStartFocal =
                      MatrixUtils.transformPoint(nextMatrix, sceneFocal);

                  final correction = focalNow - transformedStartFocal;

                  nextMatrix.translateByDouble(
                    correction.dx,
                    correction.dy,
                    0,
                    1,
                  );

                  setState((){
                    _transformationController.value = nextMatrix;
                  });
                }
              },
              onScaleEnd: (details){
                if(drawMode && drawToggle && strokes.isNotEmpty){
                  _finishStroke();
                }
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
                          CustomPaint(
                            size: Size(widget.image.width.toDouble(), widget.image.height.toDouble()),
                            painter: ImagePainter(widget.image),
                          ),
                          CustomPaint(
                            size: Size(widget.image.width.toDouble(), widget.image.height.toDouble()),
                            painter: drawMode ? StrokePainter(strokes) : EdgePainter(edges: faceDetector.graph!.edges),
                          ),
                          CustomPaint(
                            size: Size(widget.image.width.toDouble(), widget.image.height.toDouble()),
                            painter: FacePainter(
                              faces: faceDetector.graph?.faces ?? [],
                              drawLabel: !drawMode,
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

// use this to input test cases
  // @override
  // void initState(){
  //   super.initState();
  //   int i = 0;
  //   while(i < strokes.length){
  //     faceDetector.addStroke(strokes[i]);
  //     i++;
  //   }
  //   faceDetector.buildGraphAndFindFaces();
  // }

  // use for testing -> prints current strokes to terminal in a format that can be used in code
  // void _printStrokesAsCode(){
  //   for(final stroke in strokes){
  //     print('Stroke(index:${stroke.index}, points:[');
  //     for(final point in stroke.points){
  //       final dx = point.dx.toStringAsFixed(point.dx == point.dx.roundToDouble() ? 0 : 1);
  //       final dy = point.dy.toStringAsFixed(point.dy == point.dy.roundToDouble() ? 0 : 1);

  //       print('  const ui.Offset($dx,$dy),');
  //     }
  //     print(']),');
  //   }
  // }

  // for testing -> use to display vertices and edges in drawing phase 
  // CustomPaint(
  //   size: Size(
  //     widget.image.width.toDouble(),
  //     widget.image.height.toDouble(),
  //   ),
  //   painter: EdgePainter(
  //     edges: faceDetector.graph?.edges ?? [],
  //   ),
  // ),
  // CustomPaint(
  //   size: Size(
  //     widget.image.width.toDouble(),
  //     widget.image.height.toDouble(),
  //   ),
  //   painter: VertexPainter(
  //     vertice: faceDetector.graph?.vertices ?? [],
  //   ),
  // ),