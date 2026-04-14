import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../util/replay/replay.dart';
import '../util/replay/replay_file_handler.dart';
import '../util/mapPainter/map_painter.dart';
import '../util/faceDetection/face_detection_graph.dart';
import '../widgets/map_transform.dart';
import '../widgets/TabButton.dart';
import '../util/map_file_handler.dart';

class ReplayViewer extends StatefulWidget {
  const ReplayViewer({
    super.key,
    required this.replayFile,
  });

  final ReplayFile replayFile;

  @override
  State<ReplayViewer> createState() => _ReplayViewerState();
}

class _ReplayViewerState extends State<ReplayViewer> {
  Timer? _timer;

  final ValueNotifier<double> _currentTime = ValueNotifier<double>(0.0);

  bool showLabel = true;
  bool _isPlaying = false;
  bool _bottomBarCollapsed = false;
  BottomTab _activeTab = BottomTab.replay;

  final double _updatesPerSecond = 30.0;
  final double _playbackSpeed = 1.0;

  late Set<String> _selectedPlayerIds;
  MapFile? _map;
  late ui.Image _image;
  bool _mapExists = true;

  double get _maxTime {
    double maxTime = 0.0;

    for(final replay in widget.replayFile.replays){
      if(replay.positions.isNotEmpty){
        final replayEnd = replay.positions.last.time;
        if(replayEnd > maxTime){
          maxTime = replayEnd;
        }
      }
    }
    return maxTime;
  }

  @override
  void initState(){
    super.initState();
    _selectedPlayerIds = widget.replayFile.replays.map((r) => r.playerID).toSet();
    _loadReplayData();
  }

  Future<void> _loadReplayData() async {
    _map = await getMapByID(widget.replayFile.mapId);
    if(_map == null){
      _mapExists = false;  
      return;
    }
    _image = await _map!.getImage();
    if(!mounted){return;}
    setState(() {});
  }

  @override
  void dispose(){
    _timer?.cancel();
    _currentTime.dispose();
    super.dispose();
  }

  void _play(){
    if(_isPlaying) return;
    if(_maxTime <= 0) return;

    _timer?.cancel();
    setState(() => _isPlaying = true);
    _timer = Timer.periodic(
      Duration(milliseconds: (1000 / _updatesPerSecond).round()),
      (_){
        if(!mounted) return;

        final nextTime = _currentTime.value + ((1 / _updatesPerSecond) * _playbackSpeed);
        if(nextTime >= _maxTime){
          _timer?.cancel();
          _timer = null;
          _currentTime.value = _maxTime;

          if(mounted){
            setState(() => _isPlaying = false);
          }
          return;
        }
        _currentTime.value = nextTime;
      },
    );
  }

  void _pause(){
    _timer?.cancel();
    _timer = null;
    if(!mounted) return;
    setState(() => _isPlaying = false);
  }

  void _reset(){
    _timer?.cancel();
    _timer = null;
    _currentTime.value = 0.0;
    setState(() =>_isPlaying = false);
  }

  void _togglePlayPause(){
    if(_isPlaying){
      _pause();
    } else {
      _play();
    }
  }

  void _togglePlayerSelection(String playerID){
    setState((){
      if(_selectedPlayerIds.contains(playerID)){
        _selectedPlayerIds.remove(playerID);
      } else {
        _selectedPlayerIds.add(playerID);
      }
    });
  }

  void _collapseBottomBar(){
    setState(() => _bottomBarCollapsed = true);
  }

  void _openTab(BottomTab tab){
    setState((){
      _bottomBarCollapsed = false;
      _activeTab = tab;
    });
  }

  ui.Offset? _getPositionAtTime(Replay replay, double time){
    if(replay.positions.isEmpty) return null;

    if(time <= replay.positions.first.time){
      return replay.positions.first.position;
    }

    if(time >= replay.positions.last.time){
      return replay.positions.last.position;
    }

    for(int i = 0; i < replay.positions.length - 1; i++){
      final a = replay.positions[i];
      final b = replay.positions[i + 1];
      if(time >= a.time && time <= b.time){
        final span = b.time - a.time;
        if(span <= 0) return a.position;
        final t = (time - a.time) / span;
        return ui.Offset(
          a.position.dx + ((b.position.dx - a.position.dx) * t),
          a.position.dy + ((b.position.dy - a.position.dy) * t),
        );
      }
    }
    return replay.positions.last.position;
  }

  List<Face> _getClosedFacesAtTime(double time){
    final closedIds = widget.replayFile.getClosedZoneIdsAtTime(time).toSet();
    return _map!.graph.faces.where((face){
      return closedIds.contains(face.faceID);
    }).toList();
  }

  String _formatTime(double seconds){
    final totalSeconds = seconds.floor();
    final mins = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context){
    if(_map == null && _mapExists){
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if(_map == null){
      return const Scaffold(
        body: Center(
          child: Text("Error: No map found"),
        ),
      );
    }

    final imageSize = Size(
      _image.width.toDouble(),
      _image.height.toDouble(),
    );
    final selectedReplays = widget.replayFile.replays.where(
      (replay) => _selectedPlayerIds.contains(replay.playerID),
    ).toList();
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(widget.replayFile.replayName),
        titleTextStyle: Theme.of(context).textTheme.titleLarge,
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.primary,
        ),
        backgroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 0,
      ),
      body: Stack(
        children: [
          MapTransform(
            image: _image,
            child: Stack(
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    size: imageSize,
                    painter: MapPainter(
                      image: _image,
                      map: _map!,
                      drawMode: false,
                      drawLabel: true,
                    ),
                  ),
                ),
                ValueListenableBuilder<double>(
                  valueListenable: _currentTime,
                  builder: (context, time, _){
                    final closedFaces = _getClosedFacesAtTime(time);

                    return RepaintBoundary(
                      child: CustomPaint(
                        size: imageSize,
                        painter: ClosedZoneReplayPainter(
                          faces: closedFaces,
                        ),
                      ),
                    );
                  },
                ),
                ValueListenableBuilder<double>(
                  valueListenable: _currentTime,
                  builder: (context, time, _){
                    final playerDrawData = selectedReplays.map((replay){
                      return ReplayPlayerDrawData(
                        position: _getPositionAtTime(replay, time),
                        colour: replay.colour,
                        label: replay.playerName,
                      );
                    }).toList();

                    return RepaintBoundary(
                      child: CustomPaint(
                        size: imageSize,
                        painter: ReplayPlayersPainter(
                          players: playerDrawData,
                          showLabel: showLabel,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: RepaintBoundary(
              child: _bottomBarCollapsed
                  ? SafeArea(
                      top: false,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TabButton(
                            icon: Icons.add,
                            selected: false,
                            onTap: () => _openTab(_activeTab),
                          ),
                          TabButton(
                            icon: Icons.play_arrow,
                            selected: false,
                            onTap: () => _openTab(BottomTab.replay),
                          ),
                          TabButton(
                            icon: Icons.people,
                            selected: false,
                            onTap: () => _openTab(BottomTab.players),
                          ),
                          TabButton(
                            icon: Icons.settings,
                            selected: false,
                            onTap: () => _openTab(BottomTab.settings),
                          ),
                        ],
                      ),
                    )
                  : Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          constraints: const BoxConstraints(
                            minHeight: 140,
                          ),
                          margin: const EdgeInsets.only(top: 20),
                          padding: EdgeInsets.fromLTRB(
                            12,
                            18,
                            12,
                            MediaQuery.of(context).padding.bottom + 10,
                          ),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if(_activeTab == BottomTab.replay)
                                Column(
                                  children: [
                                    Row(
                                      children: [
                                        IconButton(
                                          onPressed: _reset,
                                          icon: Icon(
                                            Icons.replay,
                                            color: Theme.of(context).colorScheme.primary,
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: _togglePlayPause,
                                          icon: Icon(
                                            _isPlaying ? Icons.pause : Icons.play_arrow,
                                            color: Theme.of(context).colorScheme.primary,
                                          ),
                                        ),
                                        Expanded(
                                          child: ValueListenableBuilder<double>(
                                            valueListenable: _currentTime,
                                            builder: (context, time, _){
                                              return SliderTheme(
                                                data: SliderTheme.of(context).copyWith(
                                                  trackHeight: 4,
                                                  inactiveTrackColor: ui.Color.fromARGB(40, 0, 0, 0,),
                                                  thumbShape:
                                                      const RoundSliderThumbShape(
                                                    enabledThumbRadius: 7,
                                                  ),
                                                  overlayShape:
                                                      const RoundSliderOverlayShape(
                                                    overlayRadius: 14,
                                                  ),
                                                ),
                                                child: Slider(
                                                  value: time.clamp(
                                                    0.0,
                                                    _maxTime == 0 ? 1.0 : _maxTime,
                                                  ),
                                                  min: 0.0,
                                                  max: _maxTime == 0 ? 1.0 : _maxTime,
                                                  onChanged: (value){
                                                    _currentTime.value = value;
                                                  },
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: ValueListenableBuilder<double>(
                                        valueListenable: _currentTime,
                                        builder: (context, time, _){
                                          return Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(_formatTime(time)),
                                              Text(_formatTime(_maxTime)),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              if(_activeTab == BottomTab.players)
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: widget.replayFile.replays.map((replay){
                                    final selected =
                                        _selectedPlayerIds.contains(replay.playerID);

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color.fromARGB(20, 0, 0, 0),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(12),
                                          onTap: (){
                                            _togglePlayerSelection(replay.playerID);
                                          },
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 14,
                                                height: 14,
                                                decoration: BoxDecoration(
                                                  color: replay.colour,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  '${replay.playerName} (${replay.playerID.length > 8 ? replay.playerID.substring(0, 8) : replay.playerID})',
                                                  style: const TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ),
                                              Checkbox(
                                                value: selected,
                                                onChanged: (_){
                                                  _togglePlayerSelection(
                                                    replay.playerID,
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              if (_activeTab == BottomTab.settings)
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color.fromARGB(20, 0, 0, 0),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          const Expanded(
                                            child: Text(
                                              'Show labels',
                                              style: TextStyle(
                                                color: Colors.black,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                          Checkbox(
                                            value: showLabel,
                                            onChanged: (value) {
                                              setState(() => showLabel = value ?? true);
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          child: Row(
                            children: [
                              TabButton(
                                icon: Icons.remove,
                                selected: false,
                                onTap: _collapseBottomBar,
                              ),
                              TabButton(
                                icon: Icons.play_arrow,
                                selected: _activeTab == BottomTab.replay,
                                onTap: () => _openTab(BottomTab.replay),
                              ),
                              TabButton(
                                icon: Icons.people,
                                selected: _activeTab == BottomTab.players,
                                onTap: () => _openTab(BottomTab.players),
                              ),
                              TabButton(
                                icon: Icons.settings,
                                selected: _activeTab == BottomTab.settings,
                                onTap: () => _openTab(BottomTab.settings),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

enum BottomTab {
  replay,
  players,
  settings,
}

class ReplayPlayerDrawData {
  final Offset? position;
  final Color colour;
  final String label;

  ReplayPlayerDrawData({
    required this.position,
    required this.colour,
    required this.label,
  });
}

class ReplayPlayersPainter extends CustomPainter {
  final List<ReplayPlayerDrawData> players;
  final bool showLabel;

  ReplayPlayersPainter({
    required this.players,
    required this.showLabel,
  });

  @override
  void paint(Canvas canvas, Size size){
    for(final player in players){
      if(player.position == null) continue;

      final glowPaint = Paint()
        ..color = player.colour.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;

      final fillPaint = Paint()
        ..color = player.colour
        ..style = PaintingStyle.fill;

      final strokePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(player.position!, 16, glowPaint);
      canvas.drawCircle(player.position!, 10, fillPaint);
      canvas.drawCircle(player.position!, 10, strokePaint);

      if(!showLabel) continue;

      final textPainter = TextPainter(
        text: TextSpan(
          text: player.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          player.position!.dx + 12,
          player.position!.dy - 10,
          textPainter.width + 12,
          textPainter.height + 6,
        ),
        const Radius.circular(8),
      );

      final bgPaint = Paint()
        ..color = const Color.fromARGB(160, 0, 0, 0)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(rect, bgPaint);

      textPainter.paint(
        canvas,
        ui.Offset(player.position!.dx + 18, player.position!.dy - 7),
      );
    }
  }

  @override
  bool shouldRepaint(covariant ReplayPlayersPainter oldDelegate){
    if(oldDelegate.showLabel != showLabel) return true;
    if(oldDelegate.players.length != players.length) return true;

    for(int i = 0; i < players.length; i++){
      final a = oldDelegate.players[i];
      final b = players[i];

      if(a.position != b.position ||
          a.colour != b.colour ||
          a.label != b.label){
        return true;
      }
    }

    return false;
  }
}

class ClosedZoneReplayPainter extends CustomPainter {
  final List<Face> faces;

  ClosedZoneReplayPainter({
    required this.faces,
  });

  @override
  void paint(Canvas canvas, Size size){
    final fillPaint = Paint()
      ..color = const Color.fromARGB(120, 255, 0, 0)
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = const Color.fromARGB(220, 255, 255, 255)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for(final face in faces){
      if(face.polygon.length < 3) continue;

      final path = Path()..moveTo(face.polygon.first.dx, face.polygon.first.dy);

      for(int i = 1; i < face.polygon.length; i++){
        path.lineTo(face.polygon[i].dx, face.polygon[i].dy);
      }

      path.close();

      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant ClosedZoneReplayPainter oldDelegate){
    if(oldDelegate.faces.length != faces.length) return true;

    for(int i = 0; i < faces.length; i++){
      final a = oldDelegate.faces[i];
      final b = faces[i];

      if(a.faceID != b.faceID) return true;
    }

    return false;
  }
}