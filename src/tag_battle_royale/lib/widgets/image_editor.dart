import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:ui' as ui;

import '../util/stroke.dart';
import '../util/mapPainter/map_painter.dart';
import '../util/faceDetection/face_detector.dart';
import '../util/faceDetection/face_detection_graph.dart';
import '../util/map_file_handler.dart';
import '../widgets/map_transform.dart';

class ImageEditor extends StatefulWidget {
  const ImageEditor({super.key, required this.image, required this.imageBounds});
  final ui.Image image;
  final LatLngBounds imageBounds;

  @override
  ImageEditorState createState() => ImageEditorState();
}

class ImageEditorState extends State<ImageEditor> {
  final List<Stroke> strokes = [];
  final List<Stroke> redoStrokes = [];

  bool drawMode = true;
  bool drawToggle = false;
  String mapName = "Unnamed Map";

  FaceDetector faceDetector = FaceDetector();

  @override
  void initState(){
    super.initState();
    int i = 0;
    while (i < strokes.length){
      faceDetector.addStroke(strokes[i]);
      i++;
    }
    faceDetector.buildGraphAndFindFaces();
  }

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

  void _togglePen(){
    if(!drawMode) return;
    setState(() => drawToggle = !drawToggle);
  }

  void _finishDrawMode(){
    setState((){
      drawMode = false;
      drawToggle = false;
    });
  }

  void _backToDrawMode(){
    setState((){
      drawMode = true;
    });
  }

  void _finishStroke(){
    if(strokes.isEmpty) return;
    setState((){
      final stroke = strokes.last;
      faceDetector.addStroke(stroke);
      faceDetector.buildGraphAndFindFaces();
    });
  }

  bool _inBounds(Offset p){
    return p.dx >= 0 &&
        p.dy >= 0 &&
        p.dx <= widget.image.width.toDouble() &&
        p.dy <= widget.image.height.toDouble();
  }

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
    final imageSize = Size(
      widget.image.width.toDouble(),
      widget.image.height.toDouble(),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: GestureDetector(
          onTap: _editMapName,
          child: Text(mapName),
        ),
        titleTextStyle: const TextStyle(
          color: Color.fromARGB(255, 255, 255, 255),
          fontSize: 20,
        ),
        iconTheme: const IconThemeData(
          color: Color.fromARGB(255, 255, 255, 255),
        ),
        backgroundColor: const Color.fromARGB(60, 0, 0, 0),
        leading: drawMode
            ? null
            : IconButton(
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
        onTapScene: (scenePoint){
          if(drawMode) return;

          final graph = faceDetector.graph;
          if(graph == null) return;

          final face = graph.pointInFace(scenePoint);
          if(face == null) return;

          _editFace(face);
        },
        onScaleStartScene: (details, scenePoint){
          if(drawMode && drawToggle && details.pointerCount == 1){
            if(!_inBounds(scenePoint)) return;

            setState((){
              strokes.add(
                Stroke(
                  points: [scenePoint],
                  index: strokes.length,
                ),
              );
            });
          }
        },
        onScaleUpdateScene: (details, scenePoint){
          if(drawMode && drawToggle && details.pointerCount == 1){
            if(!_inBounds(scenePoint)) return;
            if(strokes.isEmpty) return;

            setState((){
              strokes.last.add(scenePoint);
            });
          }
        },
        onScaleEnd: (details){
          if(drawMode && drawToggle && strokes.isNotEmpty){
            _finishStroke();
          }
        },
        child: Stack(
          children: [
            CustomPaint(
              size: imageSize,
              painter: MapPainter(
                image: widget.image,
                graph: faceDetector.graph,
                strokes: strokes,
                drawMode: drawMode,
                drawLabel: !drawMode,
              ),
            ),
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
//
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