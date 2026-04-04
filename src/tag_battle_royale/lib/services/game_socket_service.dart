import 'dart:ui' show VoidCallback;
import 'package:socket_io_client/socket_io_client.dart' as IO;

typedef JsonCallback = void Function(Map<String, dynamic> data);
typedef ErrorCallback = void Function(String event, String message);
typedef LocationBroadcastCallback = void Function(Map<String, PlayerLocationInfo> players);
typedef ChatMessageCallback = void Function(ChatMessage message);

/// Player location info received from the server's broadcast.
class PlayerLocationInfo {
  final String playerId;
  final String playerName;
  final String role;
  final String status; // "active" or "stale" or "unknown" or "disconnected"
  final double? x;
  final double? y;
  final int? locationAge; // ms since last location update
  final int? disconnectedAge; // ms since disconnect (only for "disconnected" status)

  PlayerLocationInfo({
    required this.playerId,
    required this.playerName,
    required this.role,
    required this.status,
    this.x,
    this.y,
    this.locationAge,
    this.disconnectedAge,
  });

  /// Whether the server has a recent location for this player.
  bool get hasLocation => status == "active";

  /// Whether the player's location is outdated
  bool get isStale => status == "stale";

  /// Whether the player has never sent a location.
  bool get isUnknown => status == "unknown";

  /// Whether the player's socket dropped. May reconnect.
  bool get isDisconnected => status == "disconnected";

  factory PlayerLocationInfo.fromJson(Map<String, dynamic> json) {
    final loc = json['location'] as Map<String, dynamic>?;
    return PlayerLocationInfo(
      playerId: json['playerId'],
      playerName: json['playerName'],
      role: json['role'] ?? 'runner',
      status: json['status'],
      x: loc?['x']?.toDouble(),
      y: loc?['y']?.toDouble(),
      locationAge: json['locationAge'],
      disconnectedAge: json['disconnectedAge'],
    );
  }
}

/// Chat message received from the server.
class ChatMessage {
  final String playerId;
  final String playerName;
  final String text;
  final int timestamp;

  ChatMessage({
    required this.playerId,
    required this.playerName,
    required this.text,
    required this.timestamp,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      playerId: json['playerId'],
      playerName: json['playerName'],
      text: json['text'],
      timestamp: json['timestamp'],
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
  bool hasMap = false;

  // Stored information for reconnection
  String? currentGameId;
  String? currentPlayerId;

  VoidCallback? onConnected;
  VoidCallback? onDisconnected;
  JsonCallback? onGameCreated;                    // { game: { id, status, hostId, players, ... }, playerId }
  JsonCallback? onGameJoined;                     // { game: { id, status, hostId, players, ... }, playerId }
  JsonCallback? onPlayerJoined;                   // { playerId, playerName, players: [...] }
  JsonCallback? onPlayerLeft;                     // { playerId, playerName, remainingPlayers: [...] }
  JsonCallback? onGameStarted;                    // { gameId, startedAt }
  ErrorCallback? onError;                         // (event, message)
  JsonCallback? onPlayerReconnected;              // { playerId, playerName, players }
  JsonCallback? onPlayerDisconnected;             // { playerId, playerName, players }
  JsonCallback? onRejoined;                       // { game, playerId }
  JsonCallback? onMapData;                        // map json
  JsonCallback? onPlayerRoleUpdated;              // { playerId, role }
  JsonCallback? onGameDisbanded;                  // 
  LocationBroadcastCallback? onLocationBroadcast; // { playerId: PlayerLocationInfo }
  ChatMessageCallback? onChatMessage;             // ChatMessage


  GameSocketService({required this.serverUrl});

  bool get isConnected => _connected;

  
  // Connections
  void connect() {
    _socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'reconnection': true,
      'reconnectionAttempts': double.infinity, // never stop trying
      'reconnectionDelay': 1000,
      'reconnectionDelayMax': 10000, // back off up to 10s between attempts
    });

    _socket.onConnect((_) {
      _connected = true;

      // If we were in a game before disconnecting, try to rejoin automatically
      if (currentGameId != null && currentPlayerId != null) {
        _attemptRejoin();
      }

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

    _socket.on('game:map', (data) {
      final d = Map<String, dynamic>.from(data);
      onMapData?.call(d);
    });

    _socket.on('player:role:updated', (data) {
      final d = Map<String, dynamic>.from(data);
      onPlayerRoleUpdated?.call(d);
    });

    _socket.on('game:disbanded', (data) {
      final d = Map<String, dynamic>.from(data);
      onGameDisbanded?.call(d);
    });

    _socket.on('location:broadcast', (data) {
      final playersRaw = Map<String, dynamic>.from(data);

      final players = playersRaw.map((key, value) => MapEntry(
            key, PlayerLocationInfo.fromJson(Map<String, dynamic>.from(value))));

      onLocationBroadcast?.call(players);
    });

    _socket.on('chat:message', (data) {
      final d = Map<String, dynamic>.from(data);
      onChatMessage?.call(ChatMessage.fromJson(d));
    });

    _socket.on('error', (data) {
      final d = Map<String, dynamic>.from(data);
      onError?.call(d['event'] ?? 'unknown', d['message'] ?? 'Unknown error');
    });
  }

  // Rejoin after a socket reconnection
  void _attemptRejoin() {
    print('[GameSocketService] Attempting rejoin: game=$currentGameId player=$currentPlayerId');

    _socket.emitWithAck('game:rejoin', {
      'gameId': currentGameId,
      'playerId': currentPlayerId,
      'hasMap': hasMap,
    }, ack: (response) {
      final d = Map<String, dynamic>.from(response);
      if (d['ok'] == true) {
        print('[GameSocketService] Rejoin successful');
        onRejoined?.call(d);
      } else {
        // Rejoin failed, game or player no longer exists
        print('[GameSocketService] Rejoin failed: ${d['error']}');
        currentGameId = null;
        currentPlayerId = null;
        onError?.call('game:rejoin', d['error'] ?? 'Rejoin failed');
      }
    });
  }

  // --- Games ---

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

  void startGame(Map<String, dynamic> mapJson) {
    _socket.emit('game:start', {'map': mapJson});
  }

  /// Confirm that we received and processed the map data.
  void confirmMapReceived() {
    _socket.emit('game:map:received');
  }
  
  /// Intentionally leave the game, this fully removes you from the server.
  void leaveGame() {
    _socket.emit('game:leave');
    currentGameId = null;
    currentPlayerId = null;
  }

  void switchPlayerRole(String playerId, String role) {
    _socket.emitWithAck('player:role', {
      'playerId': playerId,
      'role': role,
    }, ack: (response) {
      final d = Map<String, dynamic>.from(response);
      if (d['ok'] != true) {
        onError?.call('player:role', d['error'] ?? 'Unknown error');
      }
    });
  }

  void sendChat(String text) {
    if (!_connected) return;
    _socket.emit('chat:send', {'text': text});
  }

  void sendLocation({
    required double x,
    required double y,
    int? zone,
  }) {
    if (!_connected) return;
    _socket.emit('location:update', {
      'x': x,
      'y': y,
      if (zone != null) 'zone': zone,
    });
  }

  void disconnect() {
    _socket.dispose();
    _connected = false;
    currentGameId = null;
    currentPlayerId = null;
  }
}