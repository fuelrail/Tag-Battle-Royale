import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class Player {
  Player({
    required this.id,
    required this.name,
    required this.colour,
    this.position,
  });

  final String id;
  final String name;
  Color colour;
  ui.Offset? position;

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

  void updatePlayerPosition(String id, ui.Offset? position){
    final player = _playersById[id];
    if(player == null) return;

    if(player.position == position) return;

    player.position = position;
  }

  void updatePlayerPositions(Map<String, ui.Offset> updates){
    bool changed = false;

    for(final entry in updates.entries){
      final player = _playersById[entry.key];
      if(player == null) continue;

      if(player.position != entry.value){
        player.position = entry.value;
        changed = true;
      }
    }

    if(changed){
      notifyListeners();
    }
  }

  void update(){
    notifyListeners();
  }

  Player? getPlayer(String id){
    return _playersById[id];
  }
}