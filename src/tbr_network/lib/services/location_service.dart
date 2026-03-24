import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'game_socket_service.dart';

/// Streams the device's GPS location to the server at a fixed interval.
///
/// This service keeps track of the latest position and sends it every 
/// [sendIntervalMs] milliseconds. If the GPS has no position, nothing is 
/// sent and the server will mark the player as "stale" after its threshold.
///
/// If the GPS stream errors out, the service will automatically retry.
/// The service knows we are connected to a socket via notifySocketConnected()
/// and notifySocketDisconnected(). We pause updates if we disconnect from socket.
/// 
/// Background execution is covered with the foreground service
/// notification in AndroidSettings.
class LocationService {
  final GameSocketService gameSocketService;
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

  /// This can act as a callback for logging in the game screen.
  void Function(String message)? onLog;

  LocationService({
    required this.gameSocketService,
    this.sendIntervalMs = 5000, // send every x seconds
    this.distanceFilter = 0, // optional filter if we only want to update when we move
    this.retryDelayMs = 5000, // retry every x seconds
  });

  bool get isTracking => _tracking;
  bool get hasPosition => _latestPosition != null;

  /// Start tracking. GPS events update [_latestPosition], and a timer
  /// sends the latest position to the server every [sendIntervalMs].
  void startTracking() {
    if (_tracking) {
      _log('Already tracking, ignoring startTracking()');
      return;
    }
    _tracking = true;
    _retryCount = 0;
    _socketConnected = gameSocketService.isConnected;

    _startGpsStream();

    // Only start the send timer if socket is connected
    if (_socketConnected) {
      _startSendTimer();
    } else {
      _log('Socket not connected, GPS is running but not sending');
    }

    _log('Location tracking started (sending every ${sendIntervalMs}ms if connected)');
  }

  // Sockets state
  void notifySocketConnected() {
    if (!_tracking) return;
    _socketConnected = true;
    _log('Socket reconnected, resuming location sending');
    _startSendTimer();
  }

  void notifySocketDisconnected() {
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

  /// Timer that sends the latest known position to the server at a fixed interval.
  /// Only runs while socket is connected. Only sends if GPS has provided a new
  /// update since the last send.
  void _startSendTimer() {
    _sendTimer?.cancel();

    _sendTimer = Timer.periodic(
      Duration(milliseconds: sendIntervalMs),
      (_) {
        if (!_socketConnected) return;

        if (_newPositionArrived && _latestPosition != null) {
          final pos = _latestPosition!;
          gameSocketService.sendLocation(
            lat: pos.latitude,
            lng: pos.longitude,
            heading: pos.heading,
            speed: pos.speed,
            accuracy: pos.accuracy,
          );
          _log('Sent position (${pos.latitude}, ${pos.longitude})');
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
    _log('Location tracking stopped');
  }

  void dispose() {
    stopTracking();
  }

  void _log(String message) {
    onLog?.call(message);
  }
}