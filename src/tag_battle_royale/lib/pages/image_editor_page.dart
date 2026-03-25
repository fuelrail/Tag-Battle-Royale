import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../widgets/image_editor.dart';
import 'dart:ui' as ui;

class ImageEditorPage extends StatelessWidget {
  final ui.Image image;
  final LatLngBounds imageBounds;
  const ImageEditorPage({super.key, required this.image, required this.imageBounds});

  @override
  Widget build(BuildContext context){
    return Scaffold(
      body: ImageEditor(image: image, imageBounds: imageBounds),
    );
  }
}