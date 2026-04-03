import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class UserPainter extends CustomPainter {
  final Offset? position;
  final Color colour;
  final String? label;
  final bool showLabel;

  UserPainter({
    required this.position,
    this.colour = const Color(0xFF2196F3),
    this.label = '',
    this.showLabel = false,
  });

  @override
  void paint(Canvas canvas, Size size){
    if(position == null){return;}

    final glowPaint = Paint()
      ..color = colour.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final fillPaint = Paint()
      ..color = colour
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(position!, 16, glowPaint);
    canvas.drawCircle(position!, 10, fillPaint);
    canvas.drawCircle(position!, 10, strokePaint);

      if(!showLabel || label == null){return;}

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        position!.dx + 12,
        position!.dy - 10,
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
      ui.Offset(position!.dx + 18, position!.dy - 7),
    );
  }

  @override
  bool shouldRepaint(covariant UserPainter oldDelegate){
    return oldDelegate.position != position ||
        oldDelegate.colour != colour ||
        oldDelegate.label != label ||
        oldDelegate.showLabel != showLabel;
  }
}