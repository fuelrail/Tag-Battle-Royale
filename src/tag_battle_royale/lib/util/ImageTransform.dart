import 'dart:ui' as ui;
import 'package:flutter/material.dart';

@immutable
class ImageTransform {
  final Rect imageRec;
  final Rect canvasRec;
  final double xOffset;
  final double yOffset;
  final double scale;

  const ImageTransform({
    required this.imageRec,
    required this.canvasRec,
    required this.xOffset,
    required this.yOffset,
    required this.scale,
  });

  factory ImageTransform.init(ui.Image image, Size canvasSize) {
    final imageRec = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );

    final fitted = applyBoxFit(
      BoxFit.contain,
      Size(imageRec.width, imageRec.height),
      canvasSize,
    );

    final canvasRecSize = fitted.destination;
    final xOffset = (canvasSize.width - canvasRecSize.width) / 2;
    final yOffset = (canvasSize.height - canvasRecSize.height) / 2;

    final canvasRec = Rect.fromLTWH(xOffset, yOffset, canvasRecSize.width, canvasRecSize.height);

    final scaleX = imageRec.width / canvasRec.width;
    final scaleY = imageRec.height / canvasRec.height;
    final double scale = scaleX < scaleY ? scaleX : scaleY;
    

    return ImageTransform(
      imageRec: imageRec,
      canvasRec: canvasRec,
      xOffset: xOffset,
      yOffset: yOffset,
      scale: scale
    );
  }

  bool isInsideBounds(Offset p){return canvasRec.contains(p);}

  Offset toImage(Offset canvasPoint){
    return Offset((canvasPoint.dx - xOffset) * scale, (canvasPoint.dy - yOffset) * scale);
  }
}