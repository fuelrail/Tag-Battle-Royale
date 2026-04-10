import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class Replay {
  final String playerID;
  final String playerName;
  final Color colour;
  final Stopwatch? timer;
  final List<ReplayFrame> positions = [];

  Replay({
    required this.playerID,
    required this.playerName,
    required this.colour,
    this.timer,
  });

  void start(){
    if(timer == null){return;}
    timer!.start();
  }

  void stop(){
    if(timer == null){return;}
    timer!.stop();
  }

  void reset(){
    if(timer == null){return;}
    timer!
      ..stop()
      ..reset();
    positions.clear();
  }

  void add(ui.Offset position){
    if(timer == null){return;}
    positions.add(
      ReplayFrame(
        time: timer!.elapsedMilliseconds / 1000.0,
        position: position,
      ),
    );
  }

  Map<String, dynamic> toJson(){
    return {
      'playerID': playerID,
      'playerName': playerName,
      'colour': colour.toARGB32(),
      'positions': positions.map((p) => p.toJson()).toList(),
    };
  }

  factory Replay.fromJson(Map<String, dynamic> json){
    return Replay(
      playerID: json['playerID'] as String,
      playerName: json['playerName'] as String,
      colour: Color(json['colour'] as int),
    )..positions.addAll(
        (json['positions'] as List).map(
          (p) => ReplayFrame.fromJson(Map<String, dynamic>.from(p)),
        ),
      );
  }
}

class ReplayFrame {
  final double time;
  final ui.Offset position;

  ReplayFrame({
    required this.time,
    required this.position,
  });

  Map<String, dynamic> toJson(){
    return {
      'time': time,
      'position': {
        'x': position.dx,
        'y': position.dy,
      },
    };
  }

  factory ReplayFrame.fromJson(Map<String, dynamic> json){
    final positionJson = json['position'] as Map<String, dynamic>;

    return ReplayFrame(
      time: (json['time'] as num).toDouble(),
      position: ui.Offset(
        (positionJson['x'] as num).toDouble(),
        (positionJson['y'] as num).toDouble(),
      ),
    );
  }
}