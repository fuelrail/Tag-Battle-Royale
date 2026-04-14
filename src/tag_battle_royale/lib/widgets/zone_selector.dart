import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import '../util/map_file_handler.dart';
import "../util/mapPainter/map_painter.dart";
import '../util/mapPainter/selected_zone_painter.dart';
import '../widgets/map_transform.dart';
import '../util/faceDetection/face_detection_graph.dart';


// widget for displaying a Map
class ZoneSelector extends StatefulWidget {
  const ZoneSelector({
    super.key,
    required this.map,
  });

  final MapFile map;

  @override
  State<ZoneSelector> createState() => _ZoneSelectorState();
}

class _ZoneSelectorState extends State<ZoneSelector> {
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

  Future<void> _loadImage() async {
    final img = await widget.map.getImage();
    if(!mounted) return;
    setState(() => image = img);
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
        titleTextStyle: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 20,
        ),
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.primary,
        ),
        backgroundColor: Theme.of(context).colorScheme.onPrimary,
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
                CustomPaint(
                  size: Size(image!.width.toDouble(), image!.height.toDouble()),
                  painter: SelectedZonePainter(faces: _selectedFaces,),
                ),
              ],
            ),
          ),
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