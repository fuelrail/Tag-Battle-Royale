import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class Player {
  const Player({
    required this.id,
    this.position,
    required this.colour,
    required this.name,
  });

  final String id;
  final ui.Offset? position;
  final Color colour;
  final String name;
}