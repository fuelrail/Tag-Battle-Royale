import 'package:flutter/material.dart';

import '../services/game_socket_service.dart';
import '../services/location_service.dart';
import '../util/map_file_handler.dart';
import '../util/gamesession.dart';
import 'onlinegamescreen.dart';
import '../widgets/lobby.dart';
import '../util/map_selector.dart';

import '../main.dart'; 

// --------------------------------------------------------------------------
//  Online Lobby Screen: create/join a game, wait for host to start.
// --------------------------------------------------------------------------

class OnlineConnectionScreen extends StatefulWidget {
  const OnlineConnectionScreen({
    super.key,
    required this.role,
    required this.playerName,
    this.gameCode,
  });

  // Passed from main
  final ConnectionRole role;
  final String playerName;
  final String? gameCode;

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

  bool get isHost => widget.role == ConnectionRole.host;

  @override
  void initState() {
    super.initState();
    _socket = GameSocketService(serverUrl: serverUrl);
    _location = LocationService(gameSocketService: _socket!);
    _location!.onLog = (msg) => _addLog(msg);

    _setupCallbacks();
    _socket!.connect();

    _addLog('Online mode: ${isHost ? "hosting" : "joining"}');
    _addLog('Player: ${widget.playerName}');
    if (widget.gameCode != null) {
      _addLog('Game code: ${widget.gameCode}');
    }

    // Timeout if we can't connect within 15 seconds
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && _status == 'Disconnected') {
        setState(() => _status = 'Error');
        _addLog('Connection timed out');
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

      if (_socket!.currentGameId == null) {
        if (isHost) {
          _socket!.createGame(widget.playerName);
        } else if (widget.gameCode != null) {
          _socket!.joinGame(widget.gameCode!, widget.playerName);
        }
      }
    };

    _socket!.onDisconnected = () {
      if (!mounted) return;
      setState(() => _status = 'Reconnecting...');
      _addLog('Disconnected from server, attempting to reconnect');
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

    _socket!.onPlayerJoined = (data) {
      if (!mounted) return;
      setState(() => _updatePlayerList(data['players']));
      _addLog('${data['playerName']} joined');
    };

    _socket!.onPlayerLeft = (data) {
      if (!mounted) return;
      setState(() => _updatePlayerList(data['remainingPlayers']));
      _addLog('Player ${data['playerId']} left');
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

    _socket!.onError = (event, message) {
      if (!mounted) return;
      _addLog('ERROR [$event]: $message');
      if (event == 'connection' || event == 'game:create' || event == 'game:join') {
        setState(() => _status = 'Error');
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
    // Save session for host and joiners for active game
    GameSession.save(
      gameId: _socket!.currentGameId!,
      playerId: _socket!.currentPlayerId!,
      playerName: widget.playerName,
      isHost: isHost,
      gameStarted: true,
    );

    // Start location tracking
    _location!.startTracking();

    // We pass a reference to our socket and then unhook and dispose it.
    // This way, if we dispose the game screen, it disposes its version
    // of the socket and avoids a bug where we double dispose.
    final socket = _socket!;
    final location = _location!;
    _unhookCallbacks();
    _socket = null;
    _location = null;

    // Navigate to the game screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OnlineGameScreen(
          socket: socket,
          location: location,
          gameId: socket.currentGameId!,
          isHost: isHost,
        ),
      ),
    );
  }

  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      _log.insert(0,
          '${DateTime.now().toIso8601String().substring(11, 19)} $message');
      if (_log.length > 100) _log.removeLast();
    });
  }

  void _unhookCallbacks() {
    _location?.onLog = null;
    _socket?.onConnected = null;
    _socket?.onDisconnected = null;
    _socket?.onGameCreated = null;
    _socket?.onGameJoined = null;
    _socket?.onPlayerJoined = null;
    _socket?.onPlayerLeft = null;
    _socket?.onPlayerReconnected = null;
    _socket?.onPlayerDisconnected = null;
    _socket?.onGameStarted = null;
    _socket?.onLocationBroadcast = null;
    _socket?.onChatMessage = null;
    _socket?.onError = null;
  }

  @override
  void dispose() {
    _unhookCallbacks();
    if (_socket?.currentGameId != null) _socket?.leaveGame();
    _location?.dispose();
    _socket?.disconnect();
    super.dispose();
  }

  // Game Tab Builder

  Widget _buildGameTab(BuildContext context) {
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

            if (isHost)
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Game'),
                  onPressed: () {
                    _socket!.startGame();
                    _addLog('Starting game…');
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

  @override
  Widget build(BuildContext context) {
    return LobbyLayout(
      title: _gameId != null ? 'Lobby: $_gameId' : 'Connecting...',
      isConnected: _status == 'Connected',
      players: _players,
      chatMessages: _chatMessages,
      currentPlayerId: _socket?.currentPlayerId,
      playerColourMap: _playerColourMap,
      onSendChat: (text) => _socket?.sendChat(text),
      gameTabBuilder: _buildGameTab,
      mapTabBuilder: isHost ? _buildMapTab : null,
    );
  }

  Widget _buildMapTab(BuildContext context) {
    return MapSelector(
      canCreateMaps: true,
      selectedMapName: _selectedMap?.mapName,
      onMapSelected: (map) {
        setState(() => _selectedMap = map);
        if (map != null) {
          _addLog('Selected map: ${map.mapName}');
        }
      },
    );
  }
}