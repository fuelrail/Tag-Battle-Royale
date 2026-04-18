import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:ui' as ui;

import '../util/stroke.dart';
import '../util/mapPainter/image_painter.dart';
import '../util/mapPainter/edge_painter.dart';
import '../util/mapPainter/face_painter.dart';
import '../util/mapPainter/stroke_painter.dart';
import '../util/faceDetection/face_detector.dart';
import '../util/faceDetection/face_detection_graph.dart';
import '../util/faceDetection/face_detection_point.dart';
import '../util/map_file_handler.dart';
import '../widgets/map_transform.dart';

import '../util/mapPainter/testing/vertex_painter.dart';

enum EditorTool {
  pen,
  line,
  eraser,
}

class ImageEditor extends StatefulWidget {
  const ImageEditor({
    super.key,
    required this.image,
    required this.imageBounds,
  });

  final ui.Image image;
  final LatLngBounds imageBounds;

  @override
  ImageEditorState createState() => ImageEditorState();
}

class ImageEditorState extends State<ImageEditor> {
  final List<Stroke> strokes = [];
  final List<Stroke> redoStrokes = [];
  final PointBuilder pointBuilder = PointBuilder(mergeTolerance: 6);

  bool drawMode = true;
  String mapName = "Unnamed Map";

  EditorTool? currentTool;
  bool _toolboxOpen = false;

  final FaceDetector _faceDetector = FaceDetector();

  ui.Offset? _lineStart;
  Stroke? _previewStroke;

  int _nextStrokeIndex = 0;

  static const double _eraserThreshold = 20.0;

  final ValueNotifier<int> _canvasTick = ValueNotifier(0);

  bool get drawToggle => currentTool != null;

  @override
  void initState(){
    super.initState();
    _rebuildGraph();
  }

  void _rebuildGraph(){
    _faceDetector.replaceAllStrokes(strokes);
  }

  void _repaintCanvas(){
    _canvasTick.value++;
  }
  // adds a removed stroke back to strokes
  void _redo(){
    if(redoStrokes.isEmpty) return;
    setState((){
      final stroke = redoStrokes.removeLast();
      strokes.add(stroke);
      _rebuildGraph();
    });
  }
  // removes a stroke and adds it to redoStrokes
  void _undo(){
    if(strokes.isEmpty) return;
    setState((){
      final removed = strokes.removeLast();
      redoStrokes.add(removed);
      _previewStroke = null;
      _lineStart = null;
      _rebuildGraph();
    });
  }
  // toggle for displaying the drawing tools
  void _toggleToolbox(){
    setState((){
      _toolboxOpen = !_toolboxOpen;
      if(!_toolboxOpen){
        currentTool = null;
        _previewStroke = null;
        _lineStart = null;
      }
    });
  }
  // set current tool
  void _setTool(EditorTool tool){
    setState((){
      if(currentTool == tool){
        currentTool = null;
      } else {
        currentTool = tool;
      }

      _previewStroke = null;
      _lineStart = null;
    });
    _repaintCanvas();
  }
  // moves to the naming phase
  void _finishDrawMode(){
    setState((){
      drawMode = false;
      currentTool = null;
      _toolboxOpen = false;
      _previewStroke = null;
      _lineStart = null;
    });
    _repaintCanvas();
  }
  // bad to the draw mode
  void _backToDrawMode(){
    setState((){
      _rebuildGraph();
      drawMode = true;
      currentTool = null;
      _toolboxOpen = false;
    });
  }
  // returns if a point is within the Map image
  bool _inBounds(Offset p){
    return p.dx >= 0 &&
        p.dy >= 0 &&
        p.dx <= widget.image.width.toDouble() &&
        p.dy <= widget.image.height.toDouble();
  }
  // find stroke for eraser tool
  int? _findStrokeNearPoint(ui.Offset point, double threshold){
    for(int i = strokes.length - 1; i >= 0; i--){
      final stroke = strokes[i];

      if(stroke.points.length == 1){
        if((stroke.points.first - point).distance <= threshold){
          return i;
        }
        continue;
      }

      for(int j = 0; j < stroke.points.length - 1; j++){
        final a = stroke.points[j];
        final b = stroke.points[j + 1];

        if(pointBuilder.pointLineDistance(point, a, b) <= threshold){
          return i;
        }
      }
    }

    return null;
  }
  // eraser tool
  void _eraseAtPoint(ui.Offset point){
    final index = _findStrokeNearPoint(point, _eraserThreshold);
    if(index == null) return;

    final removed = strokes.removeAt(index);
    redoStrokes.add(removed);
    _rebuildGraph();
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
              onPressed: (){
                setState((){
                  _faceDetector.deleteFace(face);
                });
                Navigator.pop(context);
              },
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
      final graph = _faceDetector.graph;
      if(graph == null) return;

      final mapFile = await MapFile.create(
        name: mapName,
        image: widget.image,
        imageBounds: widget.imageBounds,
        graph: graph,
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
  // logic for when screen is tapped
  void _handleTapScene(ui.Offset scenePoint){
    if(drawMode){
      if(!drawToggle) return;

      if(currentTool == EditorTool.eraser){
        setState((){
          _eraseAtPoint(scenePoint);
        });
      }
      return;
    }

    final graph = _faceDetector.graph;
    if(graph == null) return;

    final face = graph.pointInFace(scenePoint);
    if(face == null) return;

    _editFace(face);
  }
  // logic for the start of scaling
  void _handleScaleStart(ScaleStartDetails details, ui.Offset scenePoint){
    if(!drawMode || !drawToggle) return;
    if(details.pointerCount != 1) return;
    if(!_inBounds(scenePoint)) return;

    switch (currentTool){
      case EditorTool.pen:
        strokes.add(
          Stroke(
            points: [scenePoint],
            index: _nextStrokeIndex++,
          ),
        );
        redoStrokes.clear();
        break;

      case EditorTool.line:
        _lineStart = scenePoint;
        _previewStroke = Stroke(
          points: [scenePoint, scenePoint],
          index: _nextStrokeIndex++,
        );
        break;

      case EditorTool.eraser:
        setState((){
          _eraseAtPoint(scenePoint);
        });
        break;

      case null:
        break;
    }
    _repaintCanvas();
  }
  // handle scale update
  void _handleScaleUpdate(ScaleUpdateDetails details, ui.Offset scenePoint){
    if(!drawMode || !drawToggle) return;
    if(details.pointerCount != 1) return;
    if(!_inBounds(scenePoint)) return;

    
    switch (currentTool){
      case EditorTool.pen:
        if(strokes.isNotEmpty){
          strokes.last.add(scenePoint);
        }
        break;

      case EditorTool.line:
        if(_previewStroke != null && _lineStart != null){
          _previewStroke!.points[1] = scenePoint;
        }
        break;

      case EditorTool.eraser:
        setState((){
          _eraseAtPoint(scenePoint);
        });
        break;

      case null:
        break;
    }
    _repaintCanvas();
  }
  // handle scale end
  void _handleScaleEnd(ScaleEndDetails details){
    if(!drawMode || !drawToggle) return;

    switch (currentTool){
      case EditorTool.pen:
        if(strokes.isNotEmpty){
          _rebuildGraph();
          setState(() {});
        }
        break;

      case EditorTool.line:
        if(_previewStroke != null){
          strokes.add(_previewStroke!);
          redoStrokes.clear();
          _previewStroke = null;
          _lineStart = null;
          _rebuildGraph();
          setState(() {});
        }
        break;

      case EditorTool.eraser:
        break;

      case null:
        break;
    }
    _repaintCanvas();
  }
  // returns the icon for a given tool
  IconData _toolIcon(EditorTool tool){
    switch (tool){
      case EditorTool.pen:
        return Icons.draw;
      case EditorTool.line:
        return Icons.timeline;
      case EditorTool.eraser:
        return Icons.auto_fix_off;
    }
  }
  
  String _toolLabel(EditorTool tool){
    switch (tool){
      case EditorTool.pen:
        return 'Pen';
      case EditorTool.line:
        return 'Line';
      case EditorTool.eraser:
        return 'Eraser';
    }
  }
  // Icon Button
  Widget _buildToolButton(EditorTool tool){
    final selected = currentTool == tool;

    return IconButton(
      isSelected: selected,
      onPressed: () => _setTool(tool),
      tooltip: _toolLabel(tool),
      style: IconButton.styleFrom(
        backgroundColor: selected ? Theme.of(context).colorScheme.secondary : null,
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      icon: Icon(_toolIcon(tool)),
      selectedIcon: Icon(_toolIcon(tool)),
    );
  }

//   void _printStrokesAsCode(){
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

  @override
  Widget build(BuildContext context){
    final imageSize = Size(widget.image.width.toDouble(), widget.image.height.toDouble());

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: drawMode && _toolboxOpen ? null : 
        GestureDetector(
          onTap: _editMapName,
          child: Text(mapName),
        ),
        titleTextStyle: Theme.of(context).textTheme.titleLarge,
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.primary,
        ),
        backgroundColor: Theme.of(context).colorScheme.onPrimary,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Theme.of(context).colorScheme.primary,
          ),
          onPressed: (){
            if(drawMode && _toolboxOpen){
              setState((){
                _toolboxOpen = false;
                currentTool = null;
                _previewStroke = null;
                _lineStart = null;
              });
            } else if(!drawMode){
              _backToDrawMode();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        actions: drawMode ? 
        [
          if(!_toolboxOpen)
            IconButton(
              icon: const Icon(Icons.handyman_outlined),
              onPressed: _toggleToolbox,
            ),
          if(_toolboxOpen) ...[
            _buildToolButton(EditorTool.pen),
            _buildToolButton(EditorTool.line),
            _buildToolButton(EditorTool.eraser),
            // IconButton(
            //   icon: const Icon(Icons.print),
            //   onPressed: _printStrokesAsCode,
            //   color: Theme.of(context).colorScheme.primary,
            // ),
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: _undo,
              color: Theme.of(context).colorScheme.primary,
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              onPressed: _redo,
              color: Theme.of(context).colorScheme.primary,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _toggleToolbox,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ] :
        [],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 100),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: drawMode ? _finishDrawMode : _saveMap,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 24,
              ),
            ),
            child: Text(drawMode ? "Finished Drawing!" : "Save the Map!"),
          ),
        ),
      ),
      body: MapTransform(
        image: widget.image,
        shouldTransformOnScaleStart: (details){
          return !(drawMode && drawToggle && details.pointerCount == 1);
        },
        shouldTransformOnScaleUpdate: (details){
          return details.pointerCount >= 2 || !drawMode || !drawToggle;
        },
        onTapScene: _handleTapScene,
        onScaleStartScene: _handleScaleStart,
        onScaleUpdateScene: _handleScaleUpdate,
        onScaleEnd: _handleScaleEnd,
        child: Stack(
          children: [
            RepaintBoundary(
              child: CustomPaint(
                size: imageSize,
                painter: ImagePainter(widget.image),
              ),
            ),

            RepaintBoundary(
              child: CustomPaint(
                size: imageSize,
                painter: FacePainter(
                  faces: _faceDetector.graph?.faces ?? [],
                  drawLabel: !drawMode,
                ),
              ),
            ),

            if(!drawMode)
              RepaintBoundary(
                child: CustomPaint(
                  size: imageSize,
                  painter: EdgePainter(
                    edges: _faceDetector.graph?.edges ?? [],
                  ),
                ),
              ),

            if(drawMode)
              RepaintBoundary(
                child: ValueListenableBuilder<int>(
                  valueListenable: _canvasTick,
                  builder: (_, _, _){
                    return CustomPaint(
                      size: imageSize,
                      painter: StrokePainter([
                        ...strokes,
                       ?_previewStroke,
                      ]),
                    );
                  },
                ),
              ),
              // CustomPaint(
              //   size: Size(
              //     widget.image.width.toDouble(),
              //     widget.image.height.toDouble(),
              //   ),
              //   painter: VertexPainter(
              //     vertice: _faceDetector.graph?.vertices ?? [],
              //   ),
              // ),
          ],
        ),
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
//     _faceDetector.addStroke(strokes[i]);
//     i++;
//   }
//   _faceDetector.buildGraphAndFindFaces();
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
//     edges: _faceDetector.graph?.edges ?? [],
//   ),
// ),
// CustomPaint(
//   size: Size(
//     widget.image.width.toDouble(),
//     widget.image.height.toDouble(),
//   ),
//   painter: VertexPainter(
//     vertice: _faceDetector.graph?.vertices ?? [],
//   ),
// ),