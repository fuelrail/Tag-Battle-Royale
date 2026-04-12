import 'package:flutter/material.dart';

class PendingPlayer {
  final String socketId;
  final String playerName;

  PendingPlayer({required this.socketId, required this.playerName});
}

const List<Color> playerColours = [
  Colors.red,
  Colors.blue,
  Colors.green,
  Colors.orange,
  Colors.purple,
  Colors.teal,
  Colors.pink,
  Colors.indigo,
  Colors.amber,
  Colors.cyan,
];

class PlayerData {
  final String id;
  final String name;
  String role; // 'runner' or 'chaser'
  bool isHost;
  bool connected;
  int? caughtOrder; // order caught 1 = first, null = original chaser or not caught yet

  PlayerData({
    required this.id,
    required this.name,
    this.role = 'runner',
    this.isHost = false,
    this.connected = true,
    this.caughtOrder,
  });

  ///Host = purple, Chaser = red, Runner = black.
  Color get nameColour {
    if (isHost) return Colors.blue;
    if (role == 'chaser') return Colors.red;
    return Colors.black;
  }
}