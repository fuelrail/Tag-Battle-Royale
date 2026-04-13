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
    this.showAppBar = true,
    this.position,
    this.colour = const Color(0xFF2196F3),
  });

  final MapFile map;
  final bool showAppBar;
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
      appBar: widget.showAppBar
        ? AppBar(
            title: Text(widget.map.mapName),
            titleTextStyle: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 20,
            ),
            iconTheme: IconThemeData(
              color: Theme.of(context).colorScheme.primary,
            ),
            backgroundColor: Theme.of(context).colorScheme.onPrimary,
            elevation: 0,
          )
        : null,
      body: Stack(
        children: [ 
          MapTransform(
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