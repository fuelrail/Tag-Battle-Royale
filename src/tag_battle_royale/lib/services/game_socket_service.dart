import 'dart:ui' show VoidCallback;
import 'package:socket_io_client/socket_io_client.dart' as IO;

import '../util/player_data.dart' show ChatMessage;

typedef JsonCallback = void Function(Map<String, dynamic> data);
typedef ErrorCallback = void Function(String event, String message);
typedef LocationBroadcastCallback = void Function(Map<String, PlayerLocationInfo> players);
typedef ChatMessageCallback = void Function(ChatMessage message);
typedef ChatHistoryCallback = void Function(String channel, List<ChatMessage> messages);

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
  JsonCallback? onGameFinished;                   // { gameId, reason, finishedAt, players }
  ErrorCallback? onError;                         // (event, message)
  JsonCallback? onPlayerReconnected;              // { playerId, playerName, players }
  JsonCallback? onPlayerDisconnected;             // { playerId, playerName, players }
  JsonCallback? onRejoined;                       // { game, playerId }
  JsonCallback? onMapData;                        // { map, faceOrder, closureIntervalMs, gracePeriodMs }
  JsonCallback? onPlayerRoleUpdated;              // { playerId, role }
  JsonCallback? onGameDisbanded;                  // { reason }
  JsonCallback? onReplayReceived;                 // { playerId, replay }
  JsonCallback? onPlayerPending;                  // { socketId, playerName, pendingPlayers }
  JsonCallback? onPlayerPendingLeft;              // { socketId, playerName, pendingPlayers }
  JsonCallback? onPlayerAccepted;                 // { game, playerId }
  JsonCallback? onPlayerRejected;                 // { reason }
  JsonCallback? onPlayerKicked;                   // { reason }
  JsonCallback? onZonesReordered;                 // { faceOrder }
  JsonCallback? onReplayFileReceived;             // { replayFile }
  LocationBroadcastCallback? onLocationBroadcast; // { playerId: PlayerLocationInfo }
  ChatMessageCallback? onChatMessage;             // ChatMessage { playerId, playerName, text, timestamp, channel }
  ChatHistoryCallback? onChatHistory;             // (channel, List<ChatMessage>)


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

    _socket.on('game:finished', (data) {
      onGameFinished?.call(Map<String, dynamic>.from(data));
    });

    _socket.on('game:map', (data) {
      onMapData?.call(Map<String, dynamic>.from(data));
    });

    _socket.on('player:role:updated', (data) {
      onPlayerRoleUpdated?.call(Map<String, dynamic>.from(data));
    });

    _socket.on('game:disbanded', (data) {
      onGameDisbanded?.call(Map<String, dynamic>.from(data));
    });

    _socket.on('replay:received', (data) {
      onReplayReceived?.call(Map<String, dynamic>.from(data));
    });

    _socket.on('player:pending', (data) {
      onPlayerPending?.call(Map<String, dynamic>.from(data));
    });

    _socket.on('player:pending:left', (data) {
      onPlayerPendingLeft?.call(Map<String, dynamic>.from(data));
    });

    _socket.on('player:accepted', (data) {
      onPlayerAccepted?.call(Map<String, dynamic>.from(data));
    });

    _socket.on('player:rejected', (data) {
      onPlayerRejected?.call(Map<String, dynamic>.from(data));
    });

    _socket.on('player:kicked', (data) {
      onPlayerKicked?.call(Map<String, dynamic>.from(data));
    });

    _socket.on('game:zonesreordered', (data) {
      onZonesReordered?.call(Map<String, dynamic>.from(data));
    });

    _socket.on('replay:file', (data) {
      onReplayFileReceived?.call(Map<String, dynamic>.from(data));
    });

    _socket.on('location:broadcast', (data) {
      final playersRaw = Map<String, dynamic>.from(data);

      final players = playersRaw.map((key, value) => MapEntry(
            key, PlayerLocationInfo.fromJson(Map<String, dynamic>.from(value))));

      onLocationBroadcast?.call(players);
    });

    _socket.on('chat:message', (data) {
      onChatMessage?.call(ChatMessage.fromJson(Map<String, dynamic>.from(data)));
    });

    _socket.on('chat:history', (data) {
      final d = Map<String, dynamic>.from(data);
      final channel = d['channel'] as String;
      final rawMessages = d['messages'] as List;
      final messages = rawMessages
          .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      onChatHistory?.call(channel, messages);
    });

    _socket.on('error', (data) {
      final d = Map<String, dynamic>.from(data);
      onError?.call(d['event'] ?? 'unknown', d['message'] ?? 'Unknown error');
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
        if (d['pending'] == true) {
          onGameJoined?.call(d);
        } else {
          currentGameId = d['game']?['id'];
          currentPlayerId = d['playerId'];
          onGameJoined?.call(d);
        }
      } else {
        onError?.call('game:join', d['error'] ?? 'Unknown error');
      }
    });
  }

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

  void startGame(Map<String, dynamic> mapJson, {
    required List<int> faceOrder,
    required int closureIntervalMs,
    required int gracePeriodMs,
  }) {
    _socket.emit('game:start', {
      'map': mapJson,
      'faceOrder': faceOrder,
      'closureIntervalMs': closureIntervalMs,
      'gracePeriodMs': gracePeriodMs,
    });
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

  void endGame() {
    _socket.emitWithAck('game:end', {}, ack: (response) {
      final d = Map<String, dynamic>.from(response);
      if (d['ok'] != true) {
        onError?.call('game:end', d['error'] ?? 'Unknown error');
      }
    });
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

  void reorderZones(List<int> faceOrder) {
    if (!_connected) return;
    _socket.emit('game:reorderzones', {
      'faceOrder': faceOrder,
    });
  }

  void acceptPlayer(String socketId) {
    _socket.emitWithAck('player:accept', {
      'socketId': socketId,
    }, ack: (response) {
      final d = Map<String, dynamic>.from(response);
      if (d['ok'] != true) {
        onError?.call('player:accept', d['error'] ?? 'Unknown error');
      }
    });
  }

  void rejectPlayer(String socketId) {
    _socket.emitWithAck('player:reject', {
      'socketId': socketId,
    }, ack: (response) {
      final d = Map<String, dynamic>.from(response);
      if (d['ok'] != true) {
        onError?.call('player:reject', d['error'] ?? 'Unknown error');
      }
    });
  }

  void kickPlayer(String playerId) {
    _socket.emitWithAck('player:kick', {
      'playerId': playerId,
    }, ack: (response) {
      final d = Map<String, dynamic>.from(response);
      if (d['ok'] != true) {
        onError?.call('player:kick', d['error'] ?? 'Unknown error');
      }
    });
  }

  void sendChat(String text, {String channel = 'all'}) {
    if (!_connected) return;
    _socket.emit('chat:send', {
      'text': text,
      'channel': channel,
    });
  }

  void sendLocation({
    required double x,
    required double y,
    int? zone,
    bool revealed = true,
  }) {
    if (!_connected) return;
    _socket.emit('location:update', {
      'x': x,
      'y': y,
      if (zone != null) 'zone': zone,
      'revealed': revealed,
    });
  }

  void submitReplay(Map<String, dynamic> replayJson, {
    required void Function(bool success) onResult,
  }) {
    if (!_connected) {
      onResult(false);
      return;
    }
    _socket.emitWithAck('replay:submit', {
      'replay': replayJson,
    }, ack: (response) {
      final d = Map<String, dynamic>.from(response);
      onResult(d['ok'] == true);
    });
  }

  void submitAssembledReplay(Map<String, dynamic> replayFileJson) {
    if (!_connected) return;
    _socket.emit('replay:assembled', {
      'replayFile': replayFileJson,
    });
  }

  void disconnect() {
    _socket.dispose();
    _connected = false;
    currentGameId = null;
    currentPlayerId = null;
  }
}