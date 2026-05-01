import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class Player {
  Player({
    required this.id,
    required this.name,
    required this.colour,
    this.lastSeen,
    this.position,
    this.status = 'unknown',
    this.role,
  });

  final String id;
  final String name;
  Color colour;
  ui.Offset? position;
  int? lastSeen;
  String status; // 'active', 'stale', 'unknown', 'disconnected', 'hidden'
  String? role;

  void updateColour(Color colour){
    this.colour = colour;
  }
}

class Players extends ChangeNotifier {
  final Map<String, Player> _playersById = {};

  Iterable<Player> get all => _playersById.values;

  Player? getById(String id) => _playersById[id];

  void addPlayer(Player player){
    _playersById[player.id] = player;
  }

  void updatePlayerPosition(String id, ui.Offset? position, int? age){
    final player = _playersById[id];
    if(player == null) return;
    player.position = position;
    player.lastSeen = age;
  }

  void updatePlayerStatus(String id, String status) {
    final player = _playersById[id];
    if(player == null) return;
    player.status = status;
  }

  void incrementPlayerAge(String id, int time){
    final player = _playersById[id];
    if(player == null || player.lastSeen == null){return;}
    print(player.lastSeen);
    player.lastSeen = player.lastSeen! + time;
  }

  void update(){
    notifyListeners();
  }

  Player? getPlayer(String id){
    return _playersById[id];
  }
}