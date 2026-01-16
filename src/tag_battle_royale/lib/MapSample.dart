import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart'; 
import 'dart:async';
import 'dart:typed_data';

import 'gps.dart';

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


  Future<void> _captureMap() async {
    if (_controller.isCompleted) {
      final controller = await _controller.future;

      final bytes = await controller.takeSnapshot();
      final bounds = await controller.getVisibleRegion();
      if (bytes == null) return;

    setState(() => _imageBytes = bytes);
    setState(() => _imageBounds = bounds);
    }
  }


  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(body: Center(child: Text(_error!)));
    }

    final lat = _userPosition?.target.latitude;
    final lng = _userPosition?.target.longitude;

    return Scaffold(
      body: Column(
        children: [
          const SizedBox(height: 40),
          const Text("Your location"),
          Expanded(
            child: GoogleMap(
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
              onPressed: _captureMap,
              child: const Text('Capture map image'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Lat: ${lat}\nLng: ${lng}',
              textAlign: TextAlign.center,
            ),
          ),
          if (_imageBytes != null) ...[
            Text(_imageBounds.toString()),
            SizedBox(
              height: 160,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Image.memory(_imageBytes!, fit: BoxFit.contain),
              ),
            ),],
          const SizedBox(height: 12),
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