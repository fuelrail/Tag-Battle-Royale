import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import '../util/map_file_handler.dart';
import '../util/faceDetection/face_detection_graph.dart';
import '../util/mapPainter/map_painter.dart';
import '../util/mapPainter/current_zone_painter.dart';
import '../util/mapPainter/closed_zone_painter.dart';
import '../util/mapPainter/user_painter.dart';
import '../widgets/map_transform.dart';
import '../util/player.dart';


// widget for displaying a Map
class GameDisplay extends StatefulWidget {
  const GameDisplay({
    super.key,
    required this.map,
    required this.currentZoneNotifier,
    required this.closedFacesNotifier,
    required this.players,
    this.showPlayerNames = false,
  });

  final MapFile map;

  final ValueNotifier<Face?> currentZoneNotifier;
  final ValueNotifier<List<Face>> closedFacesNotifier;

  final Players players;

  final bool showPlayerNames;

  @override
  State<GameDisplay> createState() => _GameDisplayState();
}

class _GameDisplayState extends State<GameDisplay> {
  ui.Image? image;

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

  @override
  Widget build(BuildContext context){
    if(image == null){
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final imageSize = Size(
      image!.width.toDouble(),
      image!.height.toDouble(),
    );

    return Scaffold(
      body: MapTransform(
        image: image!,
        child: Stack(
          children: [
            RepaintBoundary(
              child: CustomPaint(
                size: imageSize,
                painter: MapPainter(
                  image: image!,
                  map: widget.map,
                  drawMode: false,
                  drawLabel: true,
                ),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                size: imageSize,
                painter: ClosedZonePainter(
                  facesNotifier: widget.closedFacesNotifier,
                ),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                size: imageSize,
                painter: CurrentZonePainter(
                  faceNotifier: widget.currentZoneNotifier,
                ),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                size: imageSize,
                painter: UserPainter(
                  players: widget.players,
                  showLabel: widget.showPlayerNames,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}