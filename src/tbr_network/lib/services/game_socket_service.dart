import 'dart:ui' show VoidCallback;
import 'package:socket_io_client/socket_io_client.dart' as IO;

typedef JsonCallback = void Function(Map<String, dynamic> data);
typedef ErrorCallback = void Function(String event, String message);
typedef LocationBroadcastCallback = void Function(Map<String, PlayerLocationInfo> players);

/// Player location info received from the server's broadcast.
class PlayerLocationInfo {
  final String playerId;
  final String playerName;
  final String status; // "active" or "stale" or "unknown" or "disconnected"
  final double? lat;
  final double? lng;
  final double? heading;
  final double? speed;
  final double? accuracy;
  final int? locationAge;
  final int? disconnectedAge;

  PlayerLocationInfo({
    required this.playerId,
    required this.playerName,
    required this.status,
    this.lat,
    this.lng,
    this.heading,
    this.speed,
    this.accuracy,
    this.locationAge,
    this.disconnectedAge,
  });

  bool get hasLocation => status == "active";
  bool get isStale => status == "stale";
  bool get isUnknown => status == "unknown";
  bool get isDisconnected => status == "disconnected";

  factory PlayerLocationInfo.fromJson(Map<String, dynamic> json) {
    final loc = json['location'] as Map<String, dynamic>?;
    return PlayerLocationInfo(
      playerId: json['playerId'],
      playerName: json['playerName'],
      status: json['status'],
      lat: loc?['lat']?.toDouble(),
      lng: loc?['lng']?.toDouble(),
      heading: loc?['heading']?.toDouble(),
      speed: loc?['speed']?.toDouble(),
      accuracy: loc?['accuracy']?.toDouble(),
      locationAge: json['locationAge'],
      disconnectedAge: json['disconnectedAge'],
    );
  }
}

/// Manages the Socket.IO connection to the game server.
///
/// Callbacks are used to notify of events.
class GameSocketService {
  final String serverUrl;
  late IO.Socket _socket;
  bool _connected = false;

  String? currentGameId;
  String? currentPlayerId;

  VoidCallback? onConnected;
  VoidCallback? onDisconnected;
  JsonCallback? onGameCreated;
  JsonCallback? onGameJoined;
  JsonCallback? onPlayerJoined;
  JsonCallback? onPlayerLeft;
  JsonCallback? onGameStarted;
  ErrorCallback? onError;
  JsonCallback? onPlayerReconnected;
  JsonCallback? onPlayerDisconnected;
  LocationBroadcastCallback? onLocationBroadcast;

  GameSocketService({required this.serverUrl});

  bool get isConnected => _connected;

  void connect() {
    _socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'reconnection': true,
      'reconnectionAttempts': double.infinity,
      'reconnectionDelay': 1000,
      'reconnectionDelayMax': 10000,
    });

    _socket.onConnect((_) {
      _connected = true;
      onConnected?.call();
    });

    _socket.onDisconnect((_) {
      _connected = false;
      onDisconnected?.call();
    });

    _socket.onConnectError((error) {
      _connected = false;
      onError?.call('connection', 'Failed to connect: $error');
    });

    _socket.onConnectTimeout((_) {
      _connected = false;
      onError?.call('connection', 'Connection timed out');
    });

    _socket.on('player:joined', (data) {
      onPlayerJoined?.call(Map<String, dynamic>.from(data));
    });

    _socket.on('player:left', (data) {
      onPlayerLeft?.call(Map<String, dynamic>.from(data));
    });

    _socket.on('player:reconnected', (data) {
      onPlayerReconnected?.call(Map<String, dynamic>.from(data));
    });

    _socket.on('player:disconnected', (data) {
      onPlayerDisconnected?.call(Map<String, dynamic>.from(data));
    });

    _socket.on('game:started', (data) {
      onGameStarted?.call(Map<String, dynamic>.from(data));
    });

    _socket.on('location:broadcast', (data) {
      final playersRaw = Map<String, dynamic>.from(data);
      final players = playersRaw.map((key, value) => MapEntry(
            key, PlayerLocationInfo.fromJson(Map<String, dynamic>.from(value))));
      onLocationBroadcast?.call(players);
    });

    _socket.on('error', (data) {
      final d = Map<String, dynamic>.from(data);
      onError?.call(d['event'] ?? 'unknown', d['message'] ?? 'Unknown error');
    });
  }

  // Games
  void createGame(String playerName, {Map<String, dynamic>? config}) {
    _socket.emitWithAck('game:create', {
      'playerName': playerName,
      'config': config ?? {},
    }, ack: (response) {
      final d = Map<String, dynamic>.from(response);
      if (d['ok'] == true) {
        currentGameId = d['game']?['id'];
        currentPlayerId = d['playerId'];
        onGameCreated?.call(d);
      } else {
        onError?.call('game:create', d['error'] ?? 'Unknown error');
      }
    });
  }

  void joinGame(String gameId, String playerName) {
    _socket.emitWithAck('game:join', {
      'gameId': gameId,
      'playerName': playerName,
    }, ack: (response) {
      final d = Map<String, dynamic>.from(response);
      if (d['ok'] == true) {
        currentGameId = d['game']?['id'];
        currentPlayerId = d['playerId'];
        onGameJoined?.call(d);
      } else {
        onError?.call('game:join', d['error'] ?? 'Unknown error');
      }
    });
  }

  void startGame() {
    _socket.emit('game:start');
  }

  void leaveGame() {
    _socket.emit('game:leave');
    currentGameId = null;
    currentPlayerId = null;
  }

  // Location
  void sendLocation({
    required double lat,
    required double lng,
    double? heading,
    double? speed,
    double? accuracy,
  }) {
    if (!_connected) return;
    _socket.emit('location:update', {
      'lat': lat,
      'lng': lng,
      if (heading != null) 'heading': heading,
      if (speed != null) 'speed': speed,
      if (accuracy != null) 'accuracy': accuracy,
    });
  }

  void disconnect() {
    _socket.dispose();
    _connected = false;
    currentGameId = null;
    currentPlayerId = null;
  }
}