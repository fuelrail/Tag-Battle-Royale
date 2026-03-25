import 'dart:ui' as ui;

class Stroke{
  int index;
  List<ui.Offset> points;
  double width;
  ui.Color color;

  Stroke({
    required this.points,
    required this.index,
    this.width = 6.0,
    this.color = const ui.Color(0xFFFF0000),
  });

  void add(ui.Offset offset){
    points.add(ui.Offset(offset.dx, offset.dy));
  }
}