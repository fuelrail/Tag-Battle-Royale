import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import '../util/map_file_handler.dart';
import "../util/mapPainter/map_painter.dart";
import '../util/mapPainter/user_painter.dart';
import '../util/mapPainter/current_zone_painter.dart';
import '../widgets/map_transform.dart';
import '../util/faceDetection/face_detection_graph.dart';


// widget for displaying a Map
class MapViewer extends StatefulWidget {
  const MapViewer({
    super.key,
    required this.map,
    this.playing = false,
    this.showSelectButton = false,
    this.position,
    this.colour = const Color(0xFF2196F3),
  });

  final bool playing;
  final MapFile map;
  final bool showSelectButton;
  final ui.Offset? position;
  final Color colour;

  @override
  State<MapViewer> createState() => _MapViewerState();
}

class _MapViewerState extends State<MapViewer> {
  ui.Image? image;
  Face? _currentZone;

  @override
  void initState() {
    super.initState();
    _loadImage();
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
      body: MapTransform(
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
            if(widget.showSelectButton)
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
        ),
      ),
    );
  }
}