import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../player.dart';

class UserPainter extends CustomPainter{
  UserPainter({
    required this.players,
    this.showLabel = false,
  }): super(repaint: players);

  final Players players;
  final bool showLabel;

  static const double _radius = 10;

  @override
  void paint(Canvas canvas, Size size){

    for(final player in players.all){
      _drawPlayer(
        canvas: canvas,
        player: player,
        radius: _radius,
      );
    }
  }

  void _drawPlayer({
    required Canvas canvas,
    required Player player,
    required double radius,
  }){
    if(player.position == null) return;
    if(player.status == 'hidden') return;

    final bool isFaded = player.status == 'stale' || player.status == 'disconnected';
    final Color dotColour = isFaded
        ? Color.lerp(player.colour, Colors.grey, 0.6)!
        : player.colour;

    final glowPaint = Paint()
      ..color = dotColour.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final fillPaint = Paint()
      ..color = dotColour
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(player.position!, 16, glowPaint);
    canvas.drawCircle(player.position!, 10, fillPaint);
    canvas.drawCircle(player.position!, 10, strokePaint);

    if(!showLabel) return;
    if(player.name.trim().isEmpty) return;

    // Build label text based on status
    final String labelText;
    if (player.status == 'disconnected') {
      labelText = '${player.name}\ndisconnected';
    } else if (player.status == 'stale' && player.lastSeen != null) {
      labelText = '${player.name}\nlast seen ${player.lastSeen! ~/ 1000}s ago';
    } else {
      labelText = player.name;
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: labelText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              color: Colors.black,
              blurRadius: 4,
              offset: ui.Offset(0, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          player.position!.dx + 12,
          player.position!.dy - 10,
          textPainter.width + 12,
          textPainter.height + 6,
        ),
        const Radius.circular(8),
      );

      final bgPaint = Paint()
        ..color = const Color.fromARGB(160, 0, 0, 0)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(rect, bgPaint);
      
      textPainter.paint(
        canvas,
        ui.Offset(player.position!.dx + 18, player.position!.dy - 7),
      );
  }

  @override
  bool shouldRepaint(covariant UserPainter oldDelegate){
    return true;
  }
}