import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'gps.dart';

//TEMPTEMPTEMP
import 'dart:ui' as ui;
import 'pages/ImageEditorPage.dart';

class MapSample extends StatefulWidget {
  const MapSample({super.key});

  @override
  State<MapSample> createState() => MapSampleState();
}

class MapSampleState extends State<MapSample> {

  CameraPosition? _userPosition;
  String? _error;
  Uint8List? _imageBytes;
  LatLngBounds? _imageBounds;

  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();

  static const CameraPosition _dublinSpire = CameraPosition(
    target: LatLng(53.3498, -6.2603), // spire
    zoom: 14.4746,
  );

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    try {
      final pos = await getLocation();

      final camera = CameraPosition(
        target: LatLng(pos.latitude, pos.longitude),
        zoom: 16,
      );

      setState(() => _userPosition = camera);

      // Animate camera if map already created
      if (_controller.isCompleted) {
        final controller = await _controller.future;
        controller.animateCamera(CameraUpdate.newCameraPosition(camera));
      }
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }


  Future<ui.Image> _captureMap() async {
    if (!_controller.isCompleted) {
      throw StateError('Map controller not ready');
    }

    final controller = await _controller.future;

    final bytes = await controller.takeSnapshot();
    if (bytes == null) {
      throw StateError('Failed to capture snapshot');
    }
    final bounds = await controller.getVisibleRegion();
    setState(() {
      _imageBytes = bytes;
      _imageBounds = bounds;
    });
    return await _getImage(bytes);
  }

  Future<void> _goToEditImagePage() async{
    try {
      final image = await _captureMap();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImageEditorPage(image: image),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not capture map: $e')),
      );
    }
  }
 
 //TEMPTEMPTEMP
  Future<ui.Image> _getImage(Uint8List bytes) async{
    final codec = await ui.instantiateImageCodec(bytes);
    final frameInfo = await codec.getNextFrame();
    return frameInfo.image;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(body: Center(child: Text(_error!)));
    }

    return Scaffold(
      body: Column(
          children: [
            const SizedBox(height: 40),
            Expanded(child: GoogleMap(
                mapType: MapType.hybrid,
                initialCameraPosition: _userPosition ?? _dublinSpire,
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                onCameraMove: (pos){setState(() => _userPosition = pos);},

                onMapCreated: (GoogleMapController controller) {
                  if (!_controller.isCompleted) _controller.complete(controller);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: ElevatedButton(
                 onPressed: _goToEditImagePage,
                child: const Text('Edit!'),
              ),
            ),
          ],
        ),
    );
  }

  // @override
  // Widget build(BuildContext context) {
  //   return Scaffold(
  //     body: GoogleMap(
  //       mapType: MapType.hybrid,
  //       initialCameraPosition: _dublinSpire,
  //       onMapCreated: (GoogleMapController controller) {
  //         _controller.complete(controller);
  //       },
  //     ),
      
  //   );
  // }
}