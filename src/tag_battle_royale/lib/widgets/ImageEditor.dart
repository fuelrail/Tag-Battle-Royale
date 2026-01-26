import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:async';

import '../util/Stroke.dart';
import '../util/StrokePainter.dart';
import '../util/ImagePainter.dart';
import '../util/ImageTransform.dart';

class ImageEditor extends StatefulWidget{
  const ImageEditor({super.key, required this.image});
  final ui.Image image;
  
  @override
  _ImageEditorState createState() => _ImageEditorState();
}

class _ImageEditorState extends State<ImageEditor>{
  List<Stroke> strokes = [];
  bool drawToggle = false;
  ImageTransform? _transform;

  void _undo() {
    if (strokes.isNotEmpty) {setState(()=>strokes.removeLast());}
  }

  void _toggleDrawMode(){
    setState(()=>drawToggle = !drawToggle);
  }

  void _updateTransform(ui.Image image, Size canvasSize){
    if(_transform == null){_transform = ImageTransform.init(widget.image, canvasSize);;}
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Drawing"),
        actions: [
          IconButton(icon: const Icon(Icons.undo), onPressed: _undo),
          IconButton(isSelected: drawToggle, icon: const Icon(Icons.draw_outlined), selectedIcon: const Icon(Icons.draw), onPressed: _toggleDrawMode),

        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final canvasSize = Size(
            constraints.maxWidth,
            constraints.maxHeight,
          );

          _updateTransform(widget.image, canvasSize);
          
          
          return GestureDetector(
            onPanStart: (details) {
              if(!drawToggle){return;}
              if(!_transform!.isInsideBounds(details.localPosition)){return;}
              setState(() => strokes.add(Stroke(points: [])));
            },
            onPanUpdate: (details) {
              if(!drawToggle){return;}
              if (!_transform!.isInsideBounds(details.localPosition)) return;
              if (strokes.isEmpty){setState(() => strokes.add(Stroke(points: [])));}
              setState(() => strokes.last.points.add(details.localPosition));
            },
            child: Stack(
              children: [
                CustomPaint(
                  painter: ImagePainter(widget.image, _transform!),
                  size: Size.infinite,
                ),
                CustomPaint(
                  painter: StrokePainter(strokes, _transform!),
                  size: Size.infinite,
                )
              ],
            )
          );
        
        },
      ),
    );
  }
}




