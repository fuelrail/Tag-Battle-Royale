import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../widgets/map_viewer.dart';
import '../util/gps.dart';
import '../util/map_file_handler.dart';
import '../util/replay/replay.dart';
import '../util/replay/replay_file_handler.dart';

class ExampleGame extends StatefulWidget {
  const ExampleGame({
    super.key,
    required this.map,
    required this.playerID,
    required this.playerName,
    required this.colour,
  });

  final MapFile map;
  final String playerID;
  final String playerName;
  final Color colour;

  @override
  State<ExampleGame> createState() => _ExampleGameState();
}

class _ExampleGameState extends State<ExampleGame> {
  ui.Image? image;
  Timer? _locationTimer;
  late Replay _replay;
  ui.Offset? playerPos;

  final int updatesPerSecond = 1;
  bool _isSaving = false;

  @override
  void initState(){
    super.initState();
    _replay = Replay(
      playerID: widget.playerID,
      playerName: widget.playerName,
      colour: widget.colour,
    );
    _init();
  }

  Future<void> _init() async {
    image = await widget.map.getImage();

    if(!mounted) return;

    _replay.start();
    _startLocationUpdates();

    setState((){});
  }

  void _startLocationUpdates(){
    _locationTimer = Timer.periodic(
      Duration(milliseconds: (1000 / updatesPerSecond).toInt()),
      (_) async {
        try {
          final pos = await getLocation();

          if(!mounted || image == null) return;

          final point = _latLngToImage(pos);
          _replay.add(point);
          setState((){
            playerPos = point;
          });
        } catch (_){}
      },
    );
  }

  Offset _latLngToImage(Position pos){
    final bounds = widget.map.imageBounds;

    final lat = pos.latitude;
    final lng = pos.longitude;

    final south = bounds.southwest.latitude;
    final west = bounds.southwest.longitude;
    final north = bounds.northeast.latitude;
    final east = bounds.northeast.longitude;

    final x = (lng - west) / (east - west);
    final y = (north - lat) / (north - south);

    return Offset(
      x * image!.width,
      y * image!.height,
    );
  }

  Future<void> saveReplay() async {
    if(_isSaving) return;
    _isSaving = true;

    _locationTimer?.cancel();
    _replay.stop();

    try {
      final replayFile = await ReplayFile.create(
        map: widget.map,
        replays: [_replay],
      );


      await replayFile.saveReplayFile();
      _replay.stop();
      if(!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Replay saved')),
      );
    } catch (_){
      if(!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save replay')),
      );
    } finally {
    _isSaving = false;
  }
  }

  @override
  void dispose(){
    _locationTimer?.cancel();
    _replay.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(
        title: const Text('Example Game'),
        actions: [
          IconButton(
            onPressed: saveReplay,
            icon: const Icon(Icons.stop),
          ),
        ],
      ),
      body: MapViewer(
        map: widget.map,
        playing: true,
        position: playerPos,
      ),
    );
  }
}