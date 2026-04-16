import "package:flutter/material.dart";
import 'dart:async';
import 'dart:ui' show Offset;
import 'package:geolocator/geolocator.dart';
import 'game_socket_service.dart';
import '../util/map_file_handler.dart';

/// Streams the device's GPS location to the server at a fixed interval.
///
/// Background service is covered with the foreground service
/// notification in AndroidSettings.
/// 
/// Converts GPS coordinates to images coordinates using the map's
/// image bounds and dimensions before sending.
/// 
/// For runners, performs zone detection and determines if the runner
/// should be revealed to chasers based on zone closures and grace period.
class LocationService {
  final GameSocketService? gameSocketService;
  final int sendIntervalMs;
  final int distanceFilter;
  final int retryDelayMs;

  StreamSubscription<Position>? _gpsSubscription;
  Timer? _sendTimer;
  Position? _latestPosition;
  bool _newPositionArrived = false;
  bool _tracking = false;
  int _retryCount = 0;
  bool _socketConnected = false;
  MapFile? map;
  String role = 'runner';

  /// During grace period, runners are always hidden.
  bool inGracePeriod = false;

  /// Get the current set of closed zone faceIDs.
  Set<int> Function()? getClosedZones;
  // provided by lobby and updates the current zone for displaying
  void Function(int? id)? updateCurrentZone;
  void Function(Offset pos)? updatePlayerPosition;
  void Function(bool inClosedZone)? updateInClosedZone;
  bool inClosedZone = false;
  /// Called each time a position is sent.
  void Function(Offset position, int? zone, String role)? onFrameRecorded;


  /// This can act as a callback for logging in the game screen.
  void Function(String message)? onLog;

  LocationService({
    this.gameSocketService,
    this.sendIntervalMs = 5000, // send every x seconds
    this.distanceFilter = 0, // optional filter if we only want to update when we move
    this.retryDelayMs = 5000, // retry every x seconds
  });

  bool get isTracking => _tracking;
  bool get hasPosition => _latestPosition != null;
  bool get _hasSocket => gameSocketService != null;

  /// Start tracking. GPS events update [_latestPosition], and a timer
  /// sends the latest position to the server every [sendIntervalMs].
  void startTracking() {
    if (_tracking) {
      _log('Already tracking, ignoring startTracking()');
      return;
    }
    _tracking = true;
    _retryCount = 0;
    if (_hasSocket) {
      _socketConnected = gameSocketService!.isConnected;
    } else {
      _socketConnected = false;
    }

    _startGpsStream();

    // Only start the send timer if socket is connected
    if (_hasSocket && _socketConnected) {
      _startSendTimer();
    } else if (!_hasSocket) {
      // Offline mode, start the processing timer anyway
      _startSendTimer();
    } else {
      _log('Socket not connected, GPS is running but not sending');
    }

    _log('Location tracking started (sending every ${sendIntervalMs}ms if connected)');
  }

  // Sockets state
  void notifySocketConnected() {
    if (!_tracking || !_hasSocket) return;
    _socketConnected = true;
    _log('Socket reconnected, resuming location sending');
    _startSendTimer();
  }

  void notifySocketDisconnected() {
    if (!_hasSocket) return;
    _socketConnected = false;
    _log('Socket disconnected, pausing location sends (GPS still running)');
    _sendTimer?.cancel();
    _sendTimer = null;
  }

  /// Start listening to GPS updates.
  /// Uses AndroidSettings with a foreground service notification so the
  /// OS keeps the GPS alive when the app is backgrounded.
  /// (This means the cpu doesn't go to sleep/app is never suspended)
  void _startGpsStream() {
    _gpsSubscription?.cancel();

    _gpsSubscription = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Tag Battle Royale',
          notificationText: 'Tracking your location for the game',
          enableWakeLock: true,
        ), // Need to show a notification
      ),
    ).listen(
      (Position position) {
        _latestPosition = position;
        _newPositionArrived = true;
        _retryCount = 0;
      },
      onError: (error) {
        _log('GPS stream error: $error');
        _latestPosition = null;
        _newPositionArrived = false;
        _gpsSubscription?.cancel();
        _gpsSubscription = null;
        _attemptRetry();
      },
      cancelOnError: false,
    );
  }

  /// Retry the GPS stream after a delay
  void _attemptRetry() {
    if (!_tracking) return;

    _retryCount++;
    _log('GPS retry $_retryCount in ${retryDelayMs / 1000}s...');
    Future.delayed(Duration(milliseconds: retryDelayMs), () {
      if (!_tracking) return;
      _log('Retrying GPS stream...');
      _startGpsStream();
    });
  }

  /// Convert GPS position to image-space coordinates using the map's
  /// geo bounds and image dimensions.
  Offset? _latLngToImage(Position pos) {
    if (map == null) return null;

    final bounds = map!.imageBounds;

    final south = bounds.southwest.latitude;
    final west = bounds.southwest.longitude;
    final north = bounds.northeast.latitude;
    final east = bounds.northeast.longitude;

    final xNorm = (pos.longitude - west) / (east - west);
    final yNorm = (north - pos.latitude) / (north - south);

    return Offset(
      xNorm * map!.imageWidth,
      yNorm * map!.imageHeight,
    );
  }

  /// Timer that sends the latest known position to the server at a fixed interval.
  /// Only runs while socket is connected. Only sends if GPS has provided a new
  /// update since the last send.
  void _startSendTimer() {
    _sendTimer?.cancel();

    _sendTimer = Timer.periodic(
      Duration(milliseconds: sendIntervalMs),
      (_) {
        if (_hasSocket && !_socketConnected) return;

        if (_newPositionArrived && _latestPosition != null) {
          final pos = _latestPosition!;
          final imageOffset = _latLngToImage(pos);

          if (imageOffset == null) {
            _log('No map available for coordinate conversion');
            return;
          }

          final face = map!.graph.pointInFace(imageOffset);
          int? zone = face?.faceID;
          updateCurrentZone?.call(zone);
          updatePlayerPosition?.call(imageOffset);

          bool revealed = true;
          if (role == 'runner') {
            if (inGracePeriod) {
              // During grace period, runners are always hidden
              revealed = false;
            } else {
              final closedZones = getClosedZones?.call() ?? {};
              // Runner is hidden only if in a zone that is still open
              revealed = zone == null || closedZones.contains(zone);
            }
          }

          if(revealed != inClosedZone){updateInClosedZone?.call(revealed);}

          if (_hasSocket && _socketConnected) {
            gameSocketService!.sendLocation(
              x: imageOffset.dx,
              y: imageOffset.dy,
              zone: zone,
              revealed: revealed,
            );
          }

          onFrameRecorded?.call(imageOffset, zone, role);

          _log('Sent position (${imageOffset.dx.toStringAsFixed(1)}, ${imageOffset.dy.toStringAsFixed(1)})'
              '${zone != null ? ' zone=$zone' : ''}'
              ' revealed=$revealed');
          getClosedZones?.call();
          //final closedZones = getClosedZones?.call() ?? {};
          //_log('Zone check: zone=$zone closedZones=$closedZones revealed=$revealed getClosedZones=${getClosedZones != null}');
          _newPositionArrived = false;
        } else {
          // No position yet, server will mark us as stale after its threshold
          _log('No GPS position available to send');
        }
      },
    );
  }

  void stopTracking() {
    _gpsSubscription?.cancel();
    _gpsSubscription = null;
    _sendTimer?.cancel();
    _sendTimer = null;
    _latestPosition = null;
    _newPositionArrived = false;
    _tracking = false;
    _retryCount = 0;
    _socketConnected = false;
    getClosedZones = null;
    onFrameRecorded = null;
    inGracePeriod = false;
    _log('Location tracking stopped');
  }

  void dispose() {
    stopTracking();
  }

  void _log(String message) {
    onLog?.call(message);
  }
}