import 'dart:ui' as ui;

class Stroke{
  final List<ui.Offset> points;
  final double width;
  final ui.Color color;

  const Stroke({
    required this.points,
    this.width = 6.0,
    this.color = const ui.Color(0xFFFF0000),
  });
}