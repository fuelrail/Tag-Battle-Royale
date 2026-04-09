import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import '../util/map_file_handler.dart';
import "../util/mapPainter/map_painter.dart";
import '../util/mapPainter/user_painter.dart';
import '../util/mapPainter/current_zone_painter.dart';
import '../util/mapPainter/selected_zone_painter.dart';
import '../widgets/map_transform.dart';
import '../util/faceDetection/face_detection_graph.dart';


// widget for displaying a Map
class MapViewer extends StatefulWidget {
  const MapViewer({
    super.key,
    required this.map,
    this.playing = false,
    this.showSelectButton = false,
    this.showAppBar = true,
    this.position,
    this.colour = const Color(0xFF2196F3),
  });

  final bool playing;
  final MapFile map;
  final bool showSelectButton;
  final bool showAppBar;
  final ui.Offset? position;
  final Color colour;

  @override
  State<MapViewer> createState() => _MapViewerState();
}

class _MapViewerState extends State<MapViewer> {
  ui.Image? image;
  Face? _currentZone;

  final List<Face> _selectedFaces = [];

  bool get allSelected {
    return widget.map.graph.faces.isNotEmpty && _selectedFaces.length == widget.map.graph.faces.length;
  }

  void _toggleFace(Face face) {
    setState(() {
      if (_selectedFaces.contains(face)) {
        _selectedFaces.remove(face);
      } else {
        _selectedFaces.add(face);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _handleSelectMap() async {
    if(!allSelected){
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (context){
          return AlertDialog(
            title: const Text('Continue?'),
            content: const Text(
              'Some zones have not been selected.\nAny unselected zones will be randomly assigned.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Go back'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue'),
              ),
            ],
          );
        },
      );

      if(shouldContinue != true){return;}
    }
    if(!mounted){return;}
    final allFacesOrdered = [
      ..._selectedFaces,
      ...widget.map.graph.faces.where((face) => !_selectedFaces.contains(face)),
    ];
    Navigator.pop(context, {
      "selected": true,
      "faces": allFacesOrdered,
      });
  }

  // runs when the widget is rebuilt
  // update current zone if the incoming position changed
  @override
  void didUpdateWidget(covariant MapViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if(image == null) return;
    if(widget.position == null) return;
    if(widget.position == oldWidget.position) return;

    final zone = widget.map.graph.pointInFace(widget.position!);
    setState(() => _currentZone = zone);
  }

  Future<void> _loadImage() async {
    final img = await widget.map.getImage();
    if(!mounted) return;

    setState(() => image = img);
    if(widget.position != null) {
      final zone = widget.map.graph.pointInFace(widget.position!);
      setState(() => _currentZone = zone);
    }
  }

  @override
  Widget build(BuildContext context) {
    if(image == null) {
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
            titleTextStyle: const TextStyle(
              color: Color.fromARGB(255, 255, 255, 255),
              fontSize: 20,
            ),
            iconTheme: const IconThemeData(
              color: Color.fromARGB(255, 255, 255, 255),
            ),
            backgroundColor: const Color.fromARGB(60, 0, 0, 0),
            elevation: 0,
          )
        : null,
      body: Stack(
        children: [ 
          MapTransform(
            onTapScene: widget.showSelectButton
              ? (scenePoint) {
                  final face = widget.map.graph.pointInFace(scenePoint);
                  if (face == null) return;
                  _toggleFace(face);
                }
              : null,
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
                if (widget.showSelectButton)
                  CustomPaint(
                    size: Size(image!.width.toDouble(), image!.height.toDouble()),
                    painter: SelectedZonePainter(faces: _selectedFaces,),
                  ),
                CustomPaint(
                  size: Size(image!.width.toDouble(), image!.height.toDouble()),
                  painter: CurrentZonePainter(face: _currentZone),
                ),
                if(widget.playing && widget.position != null)
                  CustomPaint(
                    size: Size(image!.width.toDouble(), image!.height.toDouble()),
                    painter: UserPainter(
                      position: widget.position!,
                      colour: widget.colour,
                    ),
                  ),
              ],
            ),
          ),
          if(widget.showSelectButton)
          Positioned(
            left: 24,
            right: 24,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: ElevatedButton(
                onPressed: _handleSelectMap,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Select Map'),
              ),
            ),
          ),
        ]
      )
    );
  }
}