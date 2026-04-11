import 'package:flutter/material.dart';

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
    if (isHost) return Colors.purple;
    if (role == 'chaser') return Colors.red;
    return Colors.black;
  }
}