import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tag_battle_royale/widgets/game_display.dart';

import '../util/gps.dart';
import '../util/map_file_handler.dart';
import '../util/replay/replay.dart';
import '../util/replay/replay_file_handler.dart';
import '../util/faceDetection/face_detection_graph.dart';
import '../util/player.dart';

class ExampleGame extends StatefulWidget {
  ExampleGame({
    super.key,
    required this.map,
  });

  final MapFile map;
  final Players players = Players();
  final String playerID = "1";

  @override
  State<ExampleGame> createState() => _ExampleGameState();
}

class _ExampleGameState extends State<ExampleGame> {
  ui.Image? image;
  Timer? _locationTimer;
  Timer? _zoneCloseTimer;
  Stopwatch gameTimer = Stopwatch();
  late Replay _replay;

  final int updatesPerSecond = 1;
  bool _isSaving = false;

  final Random _random = Random();
  final List<Face> _closedFaces = [];

  /// faceID -> closing time in seconds
  final Map<int, double> _zoneClosings = {};

  final ValueNotifier<int?> _currentZoneNotifier = ValueNotifier(null);
  final ValueNotifier<Set<int>> _closedFacesNotifier = ValueNotifier({});

  @override
  void initState(){
    super.initState();
    widget.players.addPlayer(Player(id:"1", colour: Color.fromARGB(0, 12, 186, 192), name:"Player"));
    final player = widget.players.getPlayer(widget.playerID);
    if(player == null){return;}
    _replay = Replay(
      playerID: player.id,
      playerName: player.name,
      colour: player.colour,
      timer: gameTimer,
    );
    _init();
  }

  Future<void> _init() async {
    image = await widget.map.getImage();

    if(!mounted) return;

    _startLocationUpdates();
    _startZoneClosing();
    gameTimer.start();

    setState((){});
  }

  void _startLocationUpdates(){
    _locationTimer?.cancel();

    _locationTimer = Timer.periodic(
      Duration(milliseconds: (1000 / updatesPerSecond).toInt()),
      (_) async {
        try {
          final pos = await getLocation();

          if(!mounted || image == null) return;

          final point = _latLngToImage(pos);
          _replay.add(point);
          final currentFace = widget.map.graph.pointInFace(point);
          widget.players.updatePlayerPosition(widget.playerID, point);
          widget.players.update();
          _currentZoneNotifier.value = currentFace?.faceID;
        } catch (_){}
      },
    );
  }

  void _startZoneClosing(){
    _zoneCloseTimer?.cancel();

    _zoneCloseTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_){
        final allFaces = widget.map.graph.faces
            .where((face) => !face.isOuter)
            .toList();

        final openFaces = allFaces.where((face){
          return !_zoneClosings.containsKey(face.faceID);
        }).toList();

        if(openFaces.isEmpty){
          _zoneCloseTimer?.cancel();
          return;
        }

        final randomFace = openFaces[_random.nextInt(openFaces.length)];

        _closedFaces.add(randomFace);
        _closedFacesNotifier.value = _closedFaces.map<int>((f) => f.faceID).toSet();

        _zoneClosings[randomFace.faceID] = gameTimer.elapsedMilliseconds / 1000.0;
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
    _zoneCloseTimer?.cancel();
    _replay.stop();

    try {
      final replayFile = await ReplayFile.create(
        map: widget.map,
        replays: [_replay],
        zoneClosings: Map<int, double>.from(_zoneClosings),
      );

      await replayFile.saveReplayFile();

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
    _zoneCloseTimer?.cancel();
    _replay.stop();
    _currentZoneNotifier.dispose();
    _closedFacesNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context){
    if(image == null){
      return Scaffold(
        appBar: AppBar(
          title: const Text('Example Game'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Example Game'),
        actions: [
          IconButton(
            onPressed: saveReplay,
            icon: const Icon(Icons.stop),
          ),
        ],
      ),
      body: GameDisplay(
        map: widget.map,
        currentZoneNotifier: _currentZoneNotifier,
        closedZonesNotifier: _closedFacesNotifier,
        players: widget.players,
        showPlayerNames: false,
      ),
    );
  }
}