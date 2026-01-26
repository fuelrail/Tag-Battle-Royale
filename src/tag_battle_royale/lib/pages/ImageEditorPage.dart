import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import '../widgets/ImageEditor.dart';


class ImageEditorPage extends StatelessWidget{
  const ImageEditorPage({super.key, required this.image});

  final ui.Image image;

  @override
  Widget build(BuildContext context) {
    return(Scaffold(
      body: Column(
        children: [Expanded(child:ImageEditor(image: image))],
      ),
    ));
  }
}