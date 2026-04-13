import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class Replay {
  final String playerID;
  final String playerName;
  final Color colour;
  final DateTime? gameStartedAt;
  final List<ReplayFrame> positions = [];

  Replay({
    required this.playerID,
    required this.playerName,
    required this.colour,
    this.gameStartedAt,
  });

  // Add a frame using the elapsed time since gameStartedAt
  void add(ui.Offset position, {int? zone, String? role}) {
    if (gameStartedAt == null) return;
    final elapsed = DateTime.now().difference(gameStartedAt!).inMilliseconds / 1000.0;
    positions.add(ReplayFrame(
      time: elapsed,
      position: position,
      zone: zone,
      role: role,
    ));
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
  final int? zone; // faceID the player was in, null if outside all zones
  final String? role; // runner or chaser at this point in time

  ReplayFrame({
    required this.time,
    required this.position,
    this.zone,
    this.role,
  });

  Map<String, dynamic> toJson(){
    return {
      'time': time,
      'position': {
        'x': position.dx,
        'y': position.dy,
      },
      if (zone != null) 'zone': zone,
      if (role != null) 'role': role,
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
      zone: json['zone'] as int?,
      role: json['role'] as String?,
    );
  }
}