import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import '../util/map_file_handler.dart';
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
    required this.closedZonesNotifier,
    required this.players,
    this.showPlayerNames = false,
    this.next,
    this.onTapScene,
  });

  final MapFile map;

  final ValueNotifier<int?> currentZoneNotifier;
  final ValueNotifier<Set<int>> closedZonesNotifier;
  final ValueNotifier<int?>? next;
  final Players players;
  final Function(ui.Offset)? onTapScene;
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
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final imageSize = Size(
      image!.width.toDouble(),
      image!.height.toDouble(),
    );

    return SizedBox.expand(
      child: MapTransform(
        onTapScene: widget.onTapScene,
        image: image!,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                size: imageSize,
                painter: MapPainter(
                  image: image!,
                  map: widget.map,
                  drawMode: false,
                  next: widget.next,
                ),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                size: imageSize,
                painter: ClosedZonePainter(
                  facesNotifier: widget.closedZonesNotifier,
                  faces: widget.map.graph.faces,
                ),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                size: imageSize,
                painter: CurrentZonePainter(
                  faceNotifier: widget.currentZoneNotifier,
                  faces: widget.map.graph.faces,
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