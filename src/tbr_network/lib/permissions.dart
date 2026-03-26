import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'dart:io';

int? _sdkVersion;

Future<int> _getAndroidSdk() async {
  // Only look it up once
  if (_sdkVersion != null) return _sdkVersion!;
  if (Platform.isAndroid) {
    final info = await DeviceInfoPlugin().androidInfo;
    _sdkVersion = info.version.sdkInt;
  } else {
    _sdkVersion = 0;
  }
  return _sdkVersion!;
}

Future<bool> checkLocationPermission(BuildContext context) async {
  try {
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
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission is required to play')),
          );
        }
        return false;
      }
    }

    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location permission check failed: $e')),
      );
    }
    return false;
  }
}

Future<bool> checkBluetoothPermission(BuildContext context) async {
  try {
    if (!await Permission.bluetooth.request().isGranted ||
        !await Permission.bluetoothAdvertise.request().isGranted ||
        !await Permission.bluetoothConnect.request().isGranted ||
        !await Permission.bluetoothScan.request().isGranted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bluetooth permissions are required to play')),
        );
      }
      return false;
    }

    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bluetooth permission check failed: $e')),
      );
    }
    return false;
  }
}

Future<bool> checkNearbyWifiPermission(BuildContext context) async {
  try {
    if (!await Permission.nearbyWifiDevices.request().isGranted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Nearby Wi-Fi permission is required to play')),
        );
      }
      return false;
    }

    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nearby Wi-Fi permission check failed: $e')),
      );
    }
    return false;
  }
}
Future<bool> checkOfflinePermissions(BuildContext context) async {
  if (!await checkLocationPermission(context)) return false;

  final sdk = await _getAndroidSdk();
  if (sdk >= 31) {
    // Android SDK 31+ (Android 12+) needs bluetooth and nearby wifi permissions
    if (!await checkBluetoothPermission(context)) return false;
    if (!await checkNearbyWifiPermission(context)) return false;
  }
  return true;
}