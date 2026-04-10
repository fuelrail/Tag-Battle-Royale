import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../player.dart';

class UserPainter extends CustomPainter{
  UserPainter({
    required this.userNotifier,
    required this.otherPlayersNotifier,
    this.showLabel = false,
  }) : super(
    repaint: Listenable.merge([
      userNotifier,
      otherPlayersNotifier,
    ]),
  );

  final ValueNotifier<Player?> userNotifier;
  final ValueNotifier<List<Player>> otherPlayersNotifier;
  final bool showLabel;

  static const double _userRadius = 10;
  static const double _otherPlayerRadius = 8;

  @override
  void paint(Canvas canvas, Size size){
    final otherPlayers = otherPlayersNotifier.value;
    final user = userNotifier.value;

    for(final player in otherPlayers){
      _drawPlayer(
        canvas: canvas,
        player: player,
        radius: _otherPlayerRadius,
      );
    }

    if(user != null){
      _drawPlayer(
        canvas: canvas,
        player: user,
        radius: _userRadius,
      );
    }
  }

  void _drawPlayer({
    required Canvas canvas,
    required Player player,
    required double radius,
  }){
    if(player.position == null){return;}
    final glowPaint = Paint()
      ..color = player.colour.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final fillPaint = Paint()
      ..color = player.colour
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

    final textPainter = TextPainter(
      text: TextSpan(
        text: player.name,
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

    final textOffset = ui.Offset(
      player.position!.dx + radius + 6,
      player.position!.dy - (textPainter.height / 2),
    );

    textPainter.paint(canvas, textOffset);
  }

  @override
  bool shouldRepaint(covariant UserPainter oldDelegate){
    return oldDelegate.userNotifier != userNotifier ||
        oldDelegate.otherPlayersNotifier != otherPlayersNotifier ||
        oldDelegate.showLabel != showLabel;
  }
}