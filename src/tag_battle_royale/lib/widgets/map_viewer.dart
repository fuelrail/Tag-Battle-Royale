import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import '../util/map_file_handler.dart';
import '../util/faceDetection/face_detection_graph.dart';
import '../util/mapPainter/map_painter.dart';
import '../widgets/map_transform.dart';


// widget for displaying a Map
class MapViewer extends StatefulWidget {
  const MapViewer({
    super.key,
    required this.map,
    this.position,
    this.colour = const Color(0xFF2196F3),
  });

  final MapFile map;
  final ui.Offset? position;
  final Color colour;

  @override
  State<MapViewer> createState() => _MapViewerState();
}

class _MapViewerState extends State<MapViewer> {
  ui.Image? image;

  final List<Face> _selectedFaces = [];

  bool get allSelected {
    return widget.map.graph.faces.isNotEmpty && _selectedFaces.length == widget.map.graph.faces.length;
  }

  void _toggleFace(Face face){
    setState((){
      if(_selectedFaces.contains(face)){
        _selectedFaces.remove(face);
      } else {
        _selectedFaces.add(face);
      }
    });
  }

  @override
  void initState(){
    super.initState();
    _loadImage();
  }


  // runs when the widget is rebuilt
  // update current zone if the incoming position changed
  Future<void> _loadImage() async {
    final img = await widget.map.getImage();
    if(!mounted) return;
    setState(() => image = img);
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(widget.map.mapName),
        titleTextStyle: const TextStyle(
          color: Color.fromARGB(255, 255, 255, 255),
          fontSize: 20,
        ),
        iconTheme: const IconThemeData(
          color: Color.fromARGB(255, 255, 255, 255),
        ),
        backgroundColor: const Color.fromARGB(60, 0, 0, 0),
        elevation: 0,
      ),
      body: Stack(
        children: [ 
          MapTransform(
            onTapScene: (scenePoint){
              final face = widget.map.graph.pointInFace(scenePoint);
              if(face == null) return;

              _toggleFace(face);
            },
            image: image!,
            child: Stack(
              children: [
                CustomPaint(
                  size: Size(image!.width.toDouble(), image!.height.toDouble()),
                  painter: MapPainter(
                    image: image!,
                    map: widget.map,
                    drawMode: false,
                    drawLabel: true,
                  ),
                ),
              ],
            ),
          ),
        ]
      )
    );
  }
}