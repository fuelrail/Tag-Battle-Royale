import 'package:flutter/material.dart';

import '../services/game_socket_service.dart';
import '../services/location_service.dart';
import '../util/map_file_handler.dart';
import '../util/gamesession.dart';
import '../widgets/lobby.dart';
import '../widgets/map_selector.dart';
import '../widgets/map_viewer.dart';

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
    this.playerId,
    this.isHostOverride,
  });

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
  String? _hostId; // player ID of the game host

  final List<PlayerData> _players = [];
  final Map<String, Color> _playerColourMap = {}; // { playerId: Colour }
  final ScrollController _playersScrollController = ScrollController();
  final List<ChatMessage> _chatMessages = [];
  final List<String> _log = [];

  MapFile? _selectedMap; // host only
  bool _isStarting = false;
  MapFile? _receivedMap;

  bool _gameStarted = false;
  final Map<String, PlayerLocationInfo> _playerLocations = {};

  bool get isHost => widget.isHostOverride ?? (widget.role == ConnectionRole.host);
  bool get _isReconnecting => widget.playerId != null;
  String get _myRole {
    final me = _players.where((p) => p.id == _socket?.currentPlayerId).firstOrNull;
    return me?.role ?? 'runner';
  }

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
        _hostId = data['game']['hostId']?.toString();
        _updatePlayerList(data['game']['players']);
      });
      _addLog('Game created: $_gameId (you are ${data['playerId']})');
      // Host doesn't save session during lobby, leaving disbands the game
    };

    _socket!.onGameJoined = (data) {
      if (!mounted) return;
      setState(() {
        _gameId = data['game']['id'];
        _hostId = data['game']['hostId']?.toString();
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
        _hostId = data['game']?['hostId']?.toString() ?? _hostId;
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

      // Map and role will be set when game:map arrives
      _updateLocationRole();
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

        // Give the map to LocationService for coord conversion and zone detection
        _location?.map = _receivedMap;

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
        setState(() {}); // Rebuild to show map tab
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

    _socket!.onPlayerRoleUpdated = (data) {
      if (!mounted) return;
      final playerId = data['playerId']?.toString();
      final role = data['role']?.toString();
      
      if (playerId == null || role == null) return;
      setState(() {
        final player = _players.where((p) => p.id == playerId).firstOrNull;
        if (player != null) player.role = role;
      });
      _addLog('${_players.where((p) => p.id == playerId).firstOrNull?.name ?? playerId} is now $role');

      // If this player's role changed, update LocationService
      if (playerId == _socket?.currentPlayerId) {
        _updateLocationRole();
      }
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
    // Preserve existing roles across updates
    final existingRoles = {for (final p in _players) p.id: p.role};

    _players.clear();
    for (final player in players) {
      final id = player['id']?.toString() ?? '';
      final name = player['name']?.toString() ?? 'Unknown';
      // Use server role if present, then preserved role, then default
      final role = player['role']?.toString()
          ?? existingRoles[id]
          ?? 'runner';
      _players.add(PlayerData(
        id: id,
        name: name,
        role: role,
        isHost: id == _hostId,
      ));
    }
  }

  void _updateLocationRole() {
    _location?.role = _myRole;
  }

  // --- Role switching ---

  void _switchRole(String playerId) {
    if (_gameStarted) {
      _confirmRoleSwitch(playerId);
    } else {
      _doRoleSwitch(playerId);
    }
  }

  Future<void> _confirmRoleSwitch(String playerId) async {
    final player = _players.where((p) => p.id == playerId).firstOrNull;
    if (player == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch role?'),
        content: Text(
          'The game is in progress. Are you sure you want to switch '
          '${player.name} to ${player.role == 'runner' ? 'chaser' : 'runner'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _doRoleSwitch(playerId);
    }
  }

  void _doRoleSwitch(String playerId) {
    final player = _players.where((p) => p.id == playerId).firstOrNull;
    if (player == null) return;
    final newRole = player.role == 'runner' ? 'chaser' : 'runner';

    setState(() => player.role = newRole);

    _socket?.switchPlayerRole(playerId, newRole);

    // If we switched our own role, update LocationService
    if (playerId == _socket?.currentPlayerId) {
      _updateLocationRole();
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

    // Set role and start tracking
    _updateLocationRole();
    _location?.startTracking();
  }

  void _addLog(String message) {
    if (!mounted) return;
    print('${DateTime.now().toIso8601String().substring(11, 19)} $message');
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
    _socket?.onPlayerRoleUpdated = null;
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
    _playersScrollController.dispose();
    super.dispose();
  }

  // --- Sub Tab Builders for Game Tab ---

  Widget _buildRulesSubTab() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.rule, size: 48, color: Colors.grey),
          SizedBox(height: 12),
          Text('Rules coming soon', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildPlayersSubTab() {
    if (_players.isEmpty) {
      return const Center(
        child: Text('No players yet', style: TextStyle(color: Colors.grey)),
      );
    }

    return Scrollbar(
      thumbVisibility: true,
      controller: _playersScrollController,
      child: ListView.builder(
        controller: _playersScrollController,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _players.length,
        itemBuilder: (context, i) {
          final player = _players[i];
          final colour = _playerColourMap.putIfAbsent(
            player.id,
            () => _kPlayerColours[_playerColourMap.length % _kPlayerColours.length],
          );
          final shortId = player.id.length > 8
              ? player.id.substring(0, 8)
              : player.id;

          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  // Colour bar
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colour,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Player name + ID
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: player.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: player.nameColour,
                            ),
                          ),
                          TextSpan(
                            text: ' ($shortId)',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Role label
                  Text(
                    player.isHost
                        ? 'Host'
                        : player.role == 'chaser'
                            ? 'Chaser'
                            : 'Runner',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  // Switch button (host user only, not on the host player card)
                  if (isHost && !player.isHost) ...[
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: () => _switchRole(player.id),
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Switch',
                        style: TextStyle(color: Colors.blue, fontSize: 13),
                      ),
                    ),
                  ] else
                    const SizedBox(width: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLogsSubTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _log.length,
      itemBuilder: (_, i) => Text(
        _log[i],
        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
      ),
    );
  }

  // --- Game Tab Builder ---

  Widget _buildGameTab(BuildContext context) {
    // If not connected, don't display game tab
    if (!_gameStarted &&
        (_status == 'Disconnected' ||
            _status == 'Reconnecting...' ||
            _status == 'Error' ||
            _gameId == null)) {
      return _buildLoadingView(context);
    }

    return Column(
      children: [
        // Top section
        _buildTopSection(context),
        // Sub-tabs
        Expanded(
          child: DefaultTabController(
            length: 3,
            initialIndex: 1, // Start on Players
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Rules'),
                    Tab(text: 'Players'),
                    Tab(text: 'Logs'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildRulesSubTab(),
                      _buildPlayersSubTab(),
                      _buildLogsSubTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingView(BuildContext context) {
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
            ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildTopSection(BuildContext context) {
    if (_gameStarted) {
      // Active game top section
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          children: [
            Text(
              'Game in progress',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_players.length} player${_players.length == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    // Lobby top section
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          // Game code
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
          const SizedBox(height: 16),

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

          // Start / waiting
          if (isHost)
            _isStarting
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(strokeWidth: 2),
                        SizedBox(width: 12),
                        Text('Starting game...'),
                      ],
                    ),
                  )
                : SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Game'),
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
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(strokeWidth: 2),
                  SizedBox(width: 12),
                  Text('Waiting for host to start…'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // --- Map tab ---

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

    // During active game, show map viewer
    if (_receivedMap != null) {
      return MapViewer(map: _receivedMap!);
    }

    return const Center(child: Text('Waiting for map data...'));
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

// Colour palette duplicated here for the game tab's player list.
// The lobby has its own copy for the Players tab.
const List<Color> _kPlayerColours = [
  Colors.red,
  Colors.blue,
  Colors.green,
  Colors.orange,
  Colors.purple,
  Colors.teal,
  Colors.pink,
  Colors.indigo,
  Colors.amber,
  Colors.cyan,
];