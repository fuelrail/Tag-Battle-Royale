import 'package:flutter/material.dart';


String formatGameTime(double totalSeconds) {
  final total = totalSeconds.floor();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

class PendingPlayer {
  final String socketId;
  final String playerName;

  PendingPlayer({required this.socketId, required this.playerName});
}

class OfflinePendingPlayer {
  final String userName;
  final String displayName;
  final String advertiserUserName; // which node they're connected to
  OfflinePendingPlayer({
    required this.userName,
    required this.displayName,
    required this.advertiserUserName,
  });
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
  double? caughtAtSeconds;

  PlayerData({
    required this.id,
    required this.name,
    this.role = 'runner',
    this.isHost = false,
    this.connected = true,
    this.caughtOrder,
    this.caughtAtSeconds,
  });

  ///Host = purple, Chaser = red, Runner = black.
  Color get nameColour {
    if (isHost) return Colors.purple;
    if (role == 'chaser') return Colors.red;
    return Colors.blue;
  }
}

class ChatMessage {
  final String playerId;
  final String playerName;
  final String text;
  final int timestamp;
  final String channel;

  ChatMessage({
    required this.playerId,
    required this.playerName,
    required this.text,
    required this.timestamp,
    required this.channel,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      playerId: json['playerId'],
      playerName: json['playerName'],
      text: json['text'],
      timestamp: json['timestamp'],
      channel: json['channel'] ?? 'all',
    );
  }
}