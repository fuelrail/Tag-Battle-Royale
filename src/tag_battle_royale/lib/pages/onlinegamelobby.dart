import 'package:flutter/material.dart';

import '../services/game_socket_service.dart';
import '../services/location_service.dart';
import '../util/map_file_handler.dart';
import '../util/gamesession.dart';
import '../widgets/lobby.dart';
import '../util/map_selector.dart';

import '../main.dart'; 

// --------------------------------------------------------------------------
//  Online Game Screen
// --------------------------------------------------------------------------

class OnlineConnectionScreen extends StatefulWidget {
  const OnlineConnectionScreen({
    super.key,
    required this.role,
    required this.playerName,
    this.gameCode,
    // For reconnecting to an active game:
    this.playerId,
    this.isHostOverride,
  });

  // Passed from main
  final ConnectionRole role;
  final String playerName;
  final String? gameCode;

  final String? playerId;
  final bool? isHostOverride;

  @override
  State<OnlineConnectionScreen> createState() => _OnlineConnectionScreenState();
}

class _OnlineConnectionScreenState extends State<OnlineConnectionScreen> {
  static const String serverUrl = 'https://tag-battle-royale.fly.dev/';

  GameSocketService? _socket;
  LocationService? _location;

  String _status = 'Disconnected';
  String? _gameId;

  final List<Map<String, String>> _players = []; // [{ id: name }]
  final Map<String, Color> _playerColourMap = {}; // { playerId: Colour }
  final List<ChatMessage> _chatMessages = [];
  final List<String> _log = [];

  MapFile? _selectedMap; // host only
  bool _isStarting = false;
  MapFile? _receivedMap;

  bool _gameStarted = false;
  final Map<String, PlayerLocationInfo> _playerLocations = {};

  bool get isHost => widget.isHostOverride ?? (widget.role == ConnectionRole.host);
  bool get _isReconnecting => widget.playerId != null;

  @override
  void initState() {
    super.initState();
    _socket = GameSocketService(serverUrl: serverUrl);
    _location = LocationService(gameSocketService: _socket!);
    _location!.onLog = (msg) => _addLog(msg);

    _setupCallbacks();

    // If reconnecting to an active game, set before connecting
    if (_isReconnecting) {
      _socket!.currentGameId = widget.gameCode;
      _socket!.currentPlayerId = widget.playerId;
      _gameId = widget.gameCode;
    }

    _socket!.connect();

    _addLog('Online mode: ${_isReconnecting ? "reconnecting" : isHost ? "hosting" : "joining"}');
    _addLog('Player: ${widget.playerName}');
    if (widget.gameCode != null) {
      _addLog('Game code: ${widget.gameCode}');
    }

    // Timeout if we can't connect within 15 seconds
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && _status == 'Disconnected') {
        setState(() => _status = 'Error');
        _addLog('Connection timed out');
        // If reconnecting, auto-pop after showing the error
        if (_isReconnecting) {
          _scheduleAutoPop();
        }
      }
    });
  }

  // --- Callbacks ---

  void _setupCallbacks() {
    _socket!.onConnected = () {
      // This check is technically unnecessary because we decided to remove
      // our callbacks on dispose, however there's no downside to removing it,
      // as it is a simple security check
      if (!mounted) return;

      setState(() => _status = 'Connected');
      _addLog('Connected to server');

      // If reconnecting, the socket will auto-rejoin via _attemptRejoin.
      // If fresh connect and no game yet, create or join.
      if (!_isReconnecting && _socket!.currentGameId == null) {
        if (isHost) {
          _socket!.createGame(widget.playerName);
        } else if (widget.gameCode != null) {
          _socket!.joinGame(widget.gameCode!, widget.playerName);
        }
      }

      // Notify location service if game is active
      if (_gameStarted) {
        _location?.notifySocketConnected();
      }
    };

    _socket!.onDisconnected = () {
      if (!mounted) return;
      setState(() => _status = 'Reconnecting...');
      _addLog('Disconnected from server, attempting to reconnect');

      if (_gameStarted) {
        _location?.notifySocketDisconnected();
      }
    };

    _socket!.onGameCreated = (data) {
      if (!mounted) return;
      setState(() {
        _gameId = data['game']['id'];
        _updatePlayerList(data['game']['players']);
      });
      _addLog('Game created: $_gameId (you are ${data['playerId']})');
      // Host doesn't save session during lobby, leaving disbands the game
    };

    _socket!.onGameJoined = (data) {
      if (!mounted) return;
      setState(() {
        _gameId = data['game']['id'];
        _updatePlayerList(data['game']['players']);
      });
      _addLog('Joined game: $_gameId');
      // Save session so joiners can reconnect to lobby if they disconnect
      GameSession.save(
        gameId: _socket!.currentGameId!,
        playerId: _socket!.currentPlayerId!,
        playerName: widget.playerName,
        isHost: false,
        gameStarted: false,
      );
    };

    _socket!.onRejoined = (data) {
      if (!mounted) return;
      setState(() {
        _gameId = data['game']?['id'] ?? _gameId;
        _gameStarted = true;
        if (data['game']?['players'] != null) {
          _updatePlayerList(data['game']['players']);
        }
      });
      _addLog('Rejoined game: $_gameId');

      GameSession.save(
        gameId: _socket!.currentGameId!,
        playerId: _socket!.currentPlayerId!,
        playerName: widget.playerName,
        isHost: isHost,
        gameStarted: true,
      );

      _location?.startTracking();
    };

    _socket!.onPlayerJoined = (data) {
      if (!mounted) return;
      setState(() => _updatePlayerList(data['players']));
      _addLog('${data['playerName']} joined');
    };

    _socket!.onPlayerLeft = (data) {
      if (!mounted) return;
      setState(() {
        _updatePlayerList(data['remainingPlayers']);
        _playerLocations.remove(data['playerId']);
      });
      _addLog('Player ${data['playerName'] ?? data['playerId']} left');
    };

    _socket!.onPlayerReconnected = (data) {
      if (!mounted) return;
      setState(() => _updatePlayerList(data['players']));
      _addLog('${data['playerName']} reconnected');
    };

    _socket!.onPlayerDisconnected = (data) {
      if (!mounted) return;
      setState(() => _updatePlayerList(data['players']));
      _addLog('${data['playerName']} disconnected');
    };

    _socket!.onGameStarted = (data) {
      if (!mounted) return;
      _addLog('Game started!');
      _onGameStarted();
    };

    _socket!.onChatMessage = (message) {
      if (!mounted) return;
      setState(() => _chatMessages.add(message));
    };

    _socket!.onMapData = (mapJson) {
      if (!mounted) return;
      try {
        _receivedMap = MapFile.fromJson(mapJson);
        // Only confirm during the starting phase (not on rejoin)
        if (!_gameStarted) {
          _socket!.confirmMapReceived();
        _addLog('Map received and confirmed');
        // Save session for host and joiners for active game
        GameSession.save(
          gameId: _socket!.currentGameId!,
          playerId: _socket!.currentPlayerId!,
          playerName: widget.playerName,
          isHost: isHost,
          gameStarted: true,
          );
        } else {
          _addLog('Map received');
        }
      } catch (e) {
        _addLog('ERROR: Failed to deserialize map: $e');
      }
    };
  
    _socket!.onLocationBroadcast = (players) {
      if (!mounted) return;
      setState(() {
        _playerLocations
          ..clear()
          ..addAll(players);
      });
    };

    _socket!.onError = (event, message) {
      if (!mounted) return;
      _addLog('ERROR [$event]: $message');

      if (event == 'connection' || event == 'game:create' || event == 'game:join') {
        setState(() => _status = 'Error');
      }
      if (event == 'game:start') {
        setState(() => _isStarting = false);
      }
      // Rejoin failed, game no longer exists
      if (event == 'game:rejoin') {
        GameSession.clear();
        setState(() => _status = 'Error');
        _addLog('Could not reconnect, game may no longer exist');
        _scheduleAutoPop();
      }
    };
  }

  void _updatePlayerList(List players) {
    _players.clear();
    for (final player in players) {
      _players.add({
        'id': player['id']?.toString() ?? '',
        'name': player['name']?.toString() ?? 'Unknown',
      });
    }
  }

  // ---

  void _onGameStarted() {
    setState(() {
      _isStarting = false;
      _gameStarted = true;
    });

    // Save session for reconnection
    GameSession.save(
      gameId: _socket!.currentGameId!,
      playerId: _socket!.currentPlayerId!,
      playerName: widget.playerName,
      isHost: isHost,
      gameStarted: true,
    );

    // Start location tracking
    _location?.startTracking();
  }

  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      _log.insert(0,
          '${DateTime.now().toIso8601String().substring(11, 19)} $message');
      if (_log.length > 100) _log.removeLast();
    });
  }

  void _scheduleAutoPop() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) Navigator.pop(context);
    });
  }

  /// Show a confirmation box when leaving an active game.
  Future<bool> _confirmLeave() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave game?'),
        content: const Text('You will be marked as disconnected. You can reconnect later from the main menu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _unhookCallbacks() {
    _location?.onLog = null;
    _socket?.onConnected = null;
    _socket?.onDisconnected = null;
    _socket?.onGameCreated = null;
    _socket?.onGameJoined = null;
    _socket?.onRejoined = null;
    _socket?.onPlayerJoined = null;
    _socket?.onPlayerLeft = null;
    _socket?.onPlayerReconnected = null;
    _socket?.onPlayerDisconnected = null;
    _socket?.onGameStarted = null;
    _socket?.onLocationBroadcast = null;
    _socket?.onChatMessage = null;
    _socket?.onMapData = null;
    _socket?.onError = null;
  }

  @override
  void dispose() {
    _unhookCallbacks();
    // Only fully leave if the game hasn't started (lobby phase).
    // If the game has started, just disconnect the socket, the server
    // will mark us as disconnected so we can reconnect.
    if (!_gameStarted && _socket?.currentGameId != null) {
      _socket?.leaveGame();
    }
    _location?.dispose();
    _socket?.disconnect();
    super.dispose();
  }

  // --- Tab Builders ---

  Widget _buildGameTab(BuildContext context) {
    // Active game view
    if (_gameStarted) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Player locations
            if (_playerLocations.isNotEmpty) ...[
              Text('Players:', style: Theme.of(context).textTheme.titleMedium),
              ..._playerLocations.entries.map((e) {
                final p = e.value;
                final locText = p.isDisconnected
                    ? 'Disconnected ${(p.disconnectedAge! / 1000).round()}s ago'
                    : p.isStale
                        ? 'Last seen ${(p.locationAge! / 1000).round()}s ago'
                        : p.isUnknown
                            ? 'No location'
                            : '(${p.lat?.toStringAsFixed(5)}, ${p.lng?.toStringAsFixed(5)})';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${p.playerName}: $locText',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                );
              }),
              const SizedBox(height: 16),
            ],

            // Log
            Text('Log:', style: Theme.of(context).textTheme.titleMedium),
            Expanded(
              child: ListView.builder(
                itemCount: _log.length,
                itemBuilder: (_, i) => Text(
                  _log[i],
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Lobby view
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status/actions
          if (_status == 'Disconnected' || _status == 'Reconnecting...')
            const Center(child: CircularProgressIndicator())
          else if (_status == 'Error')
            Center(
              child: Column(
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  const Text('Failed to connect to server'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            )
          else if (_gameId == null)
            const Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Setting up game…'),
                ],
              ),
            )
          else ...[
            // Game code display
            Center(
              child: Column(
                children: [
                  Text('Game Code',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text(
                    _gameId!,
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_players.length} player${_players.length == 1 ? '' : 's'} connected',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Select a map
            if (isHost && _selectedMap == null && !_isStarting)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Select a map in the Map tab to start',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),

            if (isHost)
              _isStarting
                  ? const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(strokeWidth: 2),
                            SizedBox(width: 16),
                            Text('Starting game...'),
                          ],
                        ),
                      ),
                    )
                  : SizedBox(
                      height: 56,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start Game'),
                        // Disabled if no map is selected
                        onPressed: _selectedMap == null
                            ? null
                            : () {
                                setState(() => _isStarting = true);
                                _socket!.startGame(_selectedMap!.toJson());
                                _addLog('Starting game, sending map to players…');
                              },
                ),
              )
            else
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(strokeWidth: 2),
                      SizedBox(width: 16),
                      Text('Waiting for host to start the game…'),
                    ],
                  ),
                ),
              ),
          ],

          const SizedBox(height: 16),

          // Log
          Text('Log:', style: Theme.of(context).textTheme.titleMedium),
          Expanded(
            child: ListView.builder(
              itemCount: _log.length,
              itemBuilder: (_, i) => Text(
                _log[i],
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapTab(BuildContext context) {
    // During lobby, host selects a map
    if (!_gameStarted) {
      return MapSelector(
        canCreateMaps: true,
        selectedMapName: _selectedMap?.mapName,
        selectedMapId: _selectedMap?.id,
        onMapSelected: (map) {
          setState(() => _selectedMap = map);
          if (map != null) {
            _addLog('Selected map: ${map.mapName}');
          }
        },
      );
    }

    return Center(
      child: _receivedMap != null
          ? Text('Map: ${_receivedMap!.mapName}')
          : const Text('No map data'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_gameStarted,
      onPopInvokedWithResult: (didPop, result) async { // might work?
        if (didPop) return;
        final shouldLeave = await _confirmLeave();
        if (shouldLeave && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: LobbyLayout(
        title: _gameStarted
            ? 'Game: ${_gameId ?? "..."}'
            : _gameId != null
                ? 'Lobby: $_gameId'
                : 'Connecting...',
        isConnected: _status == 'Connected',
        players: _players,
        chatMessages: _chatMessages,
        currentPlayerId: _socket?.currentPlayerId,
        playerColourMap: _playerColourMap,
        onSendChat: (text) => _socket?.sendChat(text),
        gameTabBuilder: _buildGameTab,
        // Host gets map tab in lobby, everyone gets it during game
        mapTabBuilder: (isHost || _gameStarted) ? _buildMapTab : null,
      ),
    );
  }
}