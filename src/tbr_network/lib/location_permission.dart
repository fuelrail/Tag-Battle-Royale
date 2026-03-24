import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

// Checks and requests location permissions.
// Shows a snackbar on the given context if denied.
Future<bool> checkLocationPermission(BuildContext context) async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enable location services')),
      );
    }
    return false;
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required to play')),
        );
      }
      return false;
    }
  }
  if (permission == LocationPermission.deniedForever) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permanently denied, open app settings')),
      );
    }
    return false;
  }

  return true;
}