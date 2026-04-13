import 'package:flutter/material.dart';
import 'dart:ui' as ui;

class MapTransform extends StatefulWidget {
  const MapTransform({
    super.key,
    required this.image,
    required this.child,
    this.minScale = 1.0,
    this.maxScale = 4.0,
    this.onTapScene,
    this.onScaleStartScene,
    this.onScaleUpdateScene,
    this.onScaleEnd,
    this.shouldTransformOnScaleStart,
    this.shouldTransformOnScaleUpdate,
  });

  final ui.Image image;
  final Widget child;

  final double minScale;
  final double maxScale;

  final void Function(Offset scenePoint)? onTapScene;
  final void Function(ScaleStartDetails details, Offset sceneFocalPoint)?
  onScaleStartScene;
  final void Function(ScaleUpdateDetails details, Offset sceneFocalPoint)?
  onScaleUpdateScene;
  final void Function(ScaleEndDetails details)? onScaleEnd;

  final bool Function(ScaleStartDetails details)? shouldTransformOnScaleStart;
  final bool Function(ScaleUpdateDetails details)? shouldTransformOnScaleUpdate;

  @override
  State<MapTransform> createState() => _MapTransformState();
}

class _MapTransformState extends State<MapTransform> {
  final TransformationController _transformationController = TransformationController();
  Matrix4 _gestureStartMatrix = Matrix4.identity();
  Offset _gestureStartSceneFocalPoint = Offset.zero;
  bool _viewerInitialised = false;
  bool _transformThisGesture = true;

  double _currentScale = 1.0;
  double _finalScale = 1.0;

  Offset _toScene(Offset point){
    final inverse = Matrix4.inverted(_transformationController.value);
    return MatrixUtils.transformPoint(inverse, point);
  }

  void _initialiseViewer(Size viewportSize){
    final imageWidth = widget.image.width.toDouble();
    final imageHeight = widget.image.height.toDouble();

    final scaleX = viewportSize.width / imageWidth;
    final scaleY = viewportSize.height / imageHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final fittedWidth = imageWidth * scale;
    final fittedHeight = imageHeight * scale;

    final dx = (viewportSize.width - fittedWidth) / 2;
    final dy = (viewportSize.height - fittedHeight) / 2;

    _transformationController.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  void dispose(){
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context){
    return LayoutBuilder(
      builder: (context, constraints){
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        if(!_viewerInitialised){
          _initialiseViewer(viewportSize);
          _viewerInitialised = true;
        }
        return ClipRect(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details){
              if(widget.onTapScene != null){
                widget.onTapScene!(_toScene(details.localPosition));
              }
            },
            onScaleStart: (details){
              _gestureStartMatrix = _transformationController.value.clone();
              _gestureStartSceneFocalPoint = _toScene(details.localFocalPoint);

              _transformThisGesture = widget.shouldTransformOnScaleStart?.call(details) ?? true;

              if(widget.onScaleStartScene != null){
                widget.onScaleStartScene!(
                  details,
                  _gestureStartSceneFocalPoint,
                );
              }
            },
            onScaleUpdate: (details){
              final currentScenePoint = _toScene(details.localFocalPoint);

              if(widget.onScaleUpdateScene != null){
                widget.onScaleUpdateScene!(details, currentScenePoint);
              }

              final shouldTransformNow = widget.shouldTransformOnScaleUpdate?.call(details) ??
                  _transformThisGesture;

              if(!shouldTransformNow) return;

              final focalNow = details.localFocalPoint;
              final sceneFocal = _gestureStartSceneFocalPoint;
              double scale = details.scale;

              if(_currentScale * scale > widget.maxScale){
                scale = widget.maxScale / _currentScale;
              } else if(_currentScale * scale < widget.minScale){
                scale = widget.minScale / _currentScale;
              }

              _finalScale = scale;

              final nextMatrix = _gestureStartMatrix.clone()
                ..translateByDouble(sceneFocal.dx, sceneFocal.dy, 0, 1)
                ..scaleByDouble(scale, scale, 1, 1)
                ..translateByDouble(-sceneFocal.dx, -sceneFocal.dy, 0, 1);

              final transformedStartFocal = MatrixUtils.transformPoint(
                nextMatrix,
                sceneFocal,
              );

              final correction = focalNow - transformedStartFocal;
              nextMatrix.translateByDouble(correction.dx, correction.dy, 0, 1);

              setState((){
                _transformationController.value = nextMatrix;
              });
            },
            onScaleEnd: (details){
              if(_transformThisGesture){
                _currentScale = _currentScale * _finalScale;
                _finalScale = 1.0;
              }

              if(widget.onScaleEnd != null){
                widget.onScaleEnd!(details);
              }
            },
            child: SizedBox(
              width: viewportSize.width,
              height: viewportSize.height,
              child: Transform(
                transform: _transformationController.value,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: widget.image.width.toDouble(),
                    height: widget.image.height.toDouble(),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}