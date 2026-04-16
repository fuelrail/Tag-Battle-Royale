import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../util/gps.dart';

import '../pages/image_editor_page.dart';

class GoogleMaps extends StatefulWidget {
  const GoogleMaps({super.key});

  @override
  State<GoogleMaps> createState() => GoogleMapsState();
}

class GoogleMapsState extends State<GoogleMaps> {

  CameraPosition? _userPosition;
  String? _error;
  LatLngBounds? _imageBounds;
  bool _showUserLocation = true;

  final Completer<GoogleMapController> _controller = Completer<GoogleMapController>();
  // initial camera position is the spire
  static const CameraPosition _dublinSpire = CameraPosition(
    target: LatLng(53.3498, -6.2603), // spire
    zoom: 14.4746,
  );

  @override
  void initState(){
    super.initState();
    _loadLocation();
  }
  // get the users position
  Future<void> _loadLocation() async {
    try {
      final pos = await getLocation();

      final camera = CameraPosition(
        target: LatLng(pos.latitude, pos.longitude),
        zoom: 16,
      );

      setState(() => _userPosition = camera);

      // Animate camera if map already created
      if(_controller.isCompleted){
        final controller = await _controller.future;
        controller.animateCamera(CameraUpdate.newCameraPosition(camera));
      }
    } catch (e){
      setState(() => _error = e.toString());
    }
  }

  // convert the currently displayed map into an image
  Future<ui.Image> _captureMap() async {
    if(!_controller.isCompleted){
      throw StateError('Map controller not ready');
    }

    // hide user dot
    setState((){
      _showUserLocation = false;
    });

    // wait for map to repaint
    await Future.delayed(const Duration(milliseconds: 300));

    final controller = await _controller.future;
    final bytes = await controller.takeSnapshot();

    // show it again
    if(mounted){
      setState((){
        _showUserLocation = true;
      });
    }

    if(bytes == null){
      throw StateError('Failed to capture snapshot');
    }

    final bounds = await controller.getVisibleRegion();
    setState((){
      _imageBounds = bounds;
    });

    return await _getImage(bytes);
  }
  // get the image and move to the editImage Page
  Future<void> _goToEditImagePage() async{
    try {
      final image = await _captureMap();
      if(!mounted) return;
      final shouldReturn = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImageEditorPage(image: image, imageBounds: _imageBounds!),
        ),
      );
      // close if should return is true
      if(shouldReturn == null){return;}
      if(!mounted) return;
      Navigator.pop(context, true);
    } catch (e){
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not capture map: $e')) );
    }
  }
  // convert image bytes to ui,Image
  Future<ui.Image> _getImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frameInfo = await codec.getNextFrame();
    return frameInfo.image;
  }

  @override
  Widget build(BuildContext context){
    if(_error != null){
      return Scaffold(
        body: Center(child: Text(_error!)),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
            title: Text("Choose an area to Play!"),
            titleTextStyle: Theme.of(context).textTheme.titleLarge,
            iconTheme: IconThemeData(
              color: Theme.of(context).colorScheme.primary,
            ),
            backgroundColor: Theme.of(context).colorScheme.onPrimary,
            elevation: 0,
          ) ,
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: _userPosition ?? _dublinSpire,
            myLocationEnabled: _showUserLocation,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            rotateGesturesEnabled: false,
            onCameraMove: (pos){setState(() => _userPosition = pos);},
            onMapCreated: (GoogleMapController controller){
              if(!_controller.isCompleted){_controller.complete(controller);}
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 100, vertical: 30),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _goToEditImagePage,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      
                    ),
                    child: const Text('Capture!'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}