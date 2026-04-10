import 'dart:async';
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
  final List<String> _log = [];

  final Map<String, List<ChatMessage>> _chatMessages = {
    'all': [],
    'runner': [],
    'chaser': [],
  };
  String _activeChannel = 'all';

  MapFile? _selectedMap; // host only
  bool _isStarting = false;
  MapFile? _receivedMap;
  List<int>? _faceOrder;       // ordered faceIDsr
  int _closureMinutes = 15;    // default 15
  int _gracePeriodSeconds = 90;
  final TextEditingController _closureMinutesController =
      TextEditingController(text: '15');
  final TextEditingController _gracePeriodController =
      TextEditingController(text: '90');

  bool _gameStarted = false;
  DateTime? _gameStartedAt;
  List<int> _activeFaceOrder = [];   // received from server
  int _activeClosureIntervalMs = 15 * 60 * 1000;
  int _activeGracePeriodMs = 90 * 1000;
  final Map<String, PlayerLocationInfo> _playerLocations = {};

  // Grace period countdown
  Timer? _graceTimer;
  int _graceSecondsRemaining = 0;

  bool get isHost => widget.isHostOverride ?? (widget.role == ConnectionRole.host);
  bool get _isReconnecting => widget.playerId != null;
  
  String get _myRole {
    final me = _players.where((p) => p.id == _socket?.currentPlayerId).firstOrNull;
    return me?.role ?? 'runner';
  }
  
  // Compute which zones have closed based on elapsed time since game start.
  Set<int> get _closedZones {
    if (_gameStartedAt == null || _activeFaceOrder.isEmpty) return {};
    // Zone closures start after grace period
    final elapsed = DateTime.now().difference(_gameStartedAt!).inMilliseconds - _activeGracePeriodMs;
    if (elapsed <= 0) return {};
    final closedCount = elapsed ~/ _activeClosureIntervalMs;
    return _activeFaceOrder.take(closedCount).toSet();
  }

  bool get _inGracePeriod {
    if (_gameStartedAt == null || _activeGracePeriodMs <= 0) return false;
    final elapsed = DateTime.now().difference(_gameStartedAt!).inMilliseconds;
    return elapsed < _activeGracePeriodMs;
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
        // If reconnecting, pop after showing the error
        if (_isReconnecting) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Connection timed out')),
          );
          Navigator.popUntil(context, (route) => route.isFirst);
        } else {
          setState(() => _status = 'Error');
          _addLog('Connection timed out');
        }
      }
    });
  }

  // --- Grace period timer ---

  void _startGraceCountdown() {
    _graceTimer?.cancel();
    _location?.inGracePeriod = _inGracePeriod;

    if (!_inGracePeriod) {
      _graceSecondsRemaining = 0;
      return;
    }

    final elapsed = DateTime.now().difference(_gameStartedAt!).inMilliseconds;
    _graceSecondsRemaining = ((_activeGracePeriodMs - elapsed) / 1000).ceil();

    _graceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _graceTimer?.cancel();
        return;
      }
      setState(() {
        _graceSecondsRemaining--;
        if (_graceSecondsRemaining <= 0) {
          _graceSecondsRemaining = 0;
          _graceTimer?.cancel();
          _graceTimer = null;
          _location?.inGracePeriod = false;
        }
      });
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
        _gameStartedAt = DateTime.fromMillisecondsSinceEpoch(data['game']?['startedAt']);
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

      // Map and role will be set when the map arrives
      _updateLocationRole();
      _location?.getClosedZones = () => _closedZones;
      _startGraceCountdown();
      // Tracking will start when the map arrives
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
      
      setState(() {
        _isStarting = false;
        _gameStarted = true;
        _gameStartedAt = DateTime.fromMillisecondsSinceEpoch(data['startedAt']);
      });
      _addLog('Game start time: $_gameStartedAt');
      _addLog('Closed zones: ${_closedZones.length}');

      if (isHost) {
        _receivedMap = _selectedMap;
        _location?.map = _selectedMap;
        _socket!.hasMap = true;
      }

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
      _location?.getClosedZones = () => _closedZones;
      _startGraceCountdown();
      if (_location?.map != null) {
        _location?.startTracking();
      }
    };

    _socket!.onChatMessage = (message) {
      if (!mounted) return;
      setState(() {
        final channel = message.channel;
        _chatMessages[channel] ??= [];
        _chatMessages[channel]!.add(message);
      });
    };

    _socket!.onChatHistory = (channel, messages) {
      if (!mounted) return;
      setState(() {
        _chatMessages[channel] = messages;
      });
      _addLog('Received ${messages.length} $channel chat messages');
    };

    _socket!.onMapData = (data) {
      if (!mounted) return;
      try {
        final mapJson = data['map'] as Map<String, dynamic>;
        _receivedMap = MapFile.fromJson(mapJson);
        _activeFaceOrder = List<int>.from(data['faceOrder']);
        _activeClosureIntervalMs = data['closureIntervalMs'];
        _activeGracePeriodMs = data['gracePeriodMs'];

        _location?.map = _receivedMap;
        _socket!.hasMap = true;

        if (_gameStarted && !_location!.isTracking) {
          _updateLocationRole();
          _location?.getClosedZones = () => _closedZones;
          _location?.startTracking();
        }

        // Only confirm during the starting phase (not on rejoin)
        if (!_gameStarted) {
          _socket!.confirmMapReceived();
          _addLog('Map received and confirmed');
          _addLog('Face order: ${_activeFaceOrder.toString()} zones, '
            'closure interval: ${_activeClosureIntervalMs ~/ 1000}s, '
            'grace period: ${_activeGracePeriodMs ~/ 1000}s');
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
          _addLog('Face order: ${_activeFaceOrder.length} zones, '
            'closure interval: ${_activeClosureIntervalMs ~/ 1000}s, '
            'grace period: ${_activeGracePeriodMs ~/ 1000}s');
        }
        setState(() {}); // Rebuild to show map tab
      } catch (e) {
        _addLog('ERROR: Failed to deserialize map: $e');
      }
    };
  
    _socket!.onLocationBroadcast = (players) {
      if (!mounted) return;
      _addLog('Broadcast: ${players.entries.map((e) {
        final p = e.value;
        final pos = p.x != null ? '(${p.x!.toStringAsFixed(1)}, ${p.y!.toStringAsFixed(1)})' : 'no pos';
        return '${p.playerName}(${p.role}) $pos ${p.status}';
      }).join(', ')}');
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
        if (role == 'chaser') {
          setState(() {
            _chatMessages['runner'] = [];
            if (_activeChannel == 'runner') {
              _activeChannel = 'chaser';
            }
          });
        }
      }
    };

    _socket!.onGameDisbanded = (data) {
      if (!mounted) return;
      final reason = data['reason']?.toString() ?? 'Game disbanded';
      GameSession.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reason)),
      );
      Navigator.popUntil(context, (route) => route.isFirst);
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not reconnect, game may no longer exist')),
        );
        Navigator.popUntil(context, (route) => route.isFirst);
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
        connected: player['connected'] ?? true,
      ));
    }
  }

  void _updateLocationRole() {
    _location?.role = _myRole;
  }

  // --- Role switching ---

  void _switchRole(String playerId) {
    if (playerId == _hostId) return;

    // Self-switches (caught button) skip confirmation popup
    if (playerId == _socket?.currentPlayerId) {
      _doRoleSwitch(playerId);
      return;
    }

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

  void _addLog(String message) {
    if (!mounted) return;
    print('${DateTime.now().toIso8601String().substring(11, 19)} $message');
    setState(() {
      _log.insert(0,
          '${DateTime.now().toIso8601String().substring(11, 19)} $message');
      if (_log.length > 100) _log.removeLast();
    });
  }

  /// Show a confirmation box when leaving an active game.
  Future<bool> _confirmLeave() async {
    final String title;
    final String content;

    if (_gameStarted) {
      title = 'Leave game?';
      content = 'You will be marked as disconnected. You can reconnect later from the main menu.';
    } else if (isHost) {
      title = 'Disband game?';
      content = 'Leaving will disband the game for all players. Are you sure?';
    } else {
      title = 'Leave game?';
      content = 'Are you sure you want to leave?';
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
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
    _socket?.onChatHistory = null;
    _socket?.onMapData = null;
    _socket?.onPlayerRoleUpdated = null;
    _socket?.onGameDisbanded = null;
    _socket?.onError = null;
  }

  @override
  void dispose() {
    _unhookCallbacks();
    _graceTimer?.cancel();
    // Only fully leave if the game hasn't started (lobby phase).
    // If the game has started, just disconnect the socket, the server
    // will mark us as disconnected so we can reconnect.
    if (!_gameStarted && _socket?.currentGameId != null) {
      _socket?.leaveGame();
    }
    _location?.dispose();
    _socket?.disconnect();
    _playersScrollController.dispose();
    _closureMinutesController.dispose();
    _gracePeriodController.dispose();
    super.dispose();
  }

  // --- Grace period banner ---

  Widget? _buildGraceBanner() {
    if (!_gameStarted || !_inGracePeriod || _graceSecondsRemaining <= 0) return null;

    final isRunner = _myRole == 'runner';
    final color = isRunner ? Colors.blue : Colors.red;
    final subtitle = isRunner ? 'Run!' : 'Stay in place!';
    final minutes = _graceSecondsRemaining ~/ 60;
    final seconds = _graceSecondsRemaining % 60;
    final timeStr = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: color,
      child: Column(
        children: [
          Text(
            'Grace Period: $timeStr',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // --- Sub Tab Builders for Game Tab ---

  Widget _buildRulesSubTab() {
    // Non-host can't see rules until game starts
    if (!isHost && !_gameStarted) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('Rules will be visible when the game starts',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final enabled = isHost && !_gameStarted;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Zone Closure', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Close a zone every '),
              SizedBox(
                width: 60,
                child: TextField(
                  controller: _closureMinutesController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  enabled: enabled,
                  onChanged: (v) {
                    final m = int.tryParse(v);
                    if (m != null && m > 0) {
                      _closureMinutes = m;
                    }
                  },
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const Text(' minutes'),
            ],
          ),
          const SizedBox(height: 20),
          Text('Grace Period', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Grace period: '),
              SizedBox(
                width: 60,
                child: TextField(
                  controller: _gracePeriodController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  enabled: enabled,
                  onChanged: (v) {
                    final s = int.tryParse(v);
                    if (s != null && s > 0) {
                      _gracePeriodSeconds = s;
                    }
                  },
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const Text(' seconds'),
            ],
          ),
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
                              color: player.connected ? player.nameColour : Colors.grey,
                            ),
                          ),
                          TextSpan(
                            text: ' ($shortId)',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (!player.connected)
                            const TextSpan(
                              text: '  disconnected',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                                fontStyle: FontStyle.italic,
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
                    onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
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
    // Active game top section
    if (_gameStarted) {
      final disconnected = _players.where((p) => !p.connected).length;
      final countText = '${_players.length} player${_players.length == 1 ? '' : 's'}';
      final disconnectedText = disconnected > 0 ? ', $disconnected disconnected' : '';
      
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
              'Code: $_gameId',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              '$countText$disconnectedText',
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
                      onPressed: (_selectedMap == null || _faceOrder == null)
                          ? null
                          : () {
                              setState(() => _isStarting = true);
                              _socket!.startGame(
                                _selectedMap!.toJson(),
                                faceOrder: _faceOrder!,
                                closureIntervalMs: _closureMinutes * 60 * 1000,
                                gracePeriodMs: _gracePeriodSeconds * 1000,
                              );
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
        onMapSelected: (map, faces) {
          setState(() {
            _selectedMap = map;
            if (faces != null) {
              _faceOrder = faces.map<int>((f) => f.faceID as int).toList();
            } else {
              _faceOrder = null;
            }
          });
          if (map != null) {
            _addLog('Selected map: ${map.mapName}');
          } else {
            _addLog('Map failed to select');
          }
        },
      );
    }

    // During active game, show map viewer
    if (_receivedMap != null) {
      final amRunner = _myRole == 'runner';
      final showCaughtButton = amRunner && !_inGracePeriod;
      return Stack(
        children: [
          MapViewer(map: _receivedMap!, showAppBar: false),
          if (amRunner)
            Positioned(
              left: 24,
              right: 24,
              bottom: 24,
              child: SafeArea(
                top: false,
                child: _CaughtButton(
                  enabled: showCaughtButton,
                  onCaught: () {
                    final myId = _socket?.currentPlayerId;
                    if (myId != null) {
                      _switchRole(myId);
                    }
                  },
                ),
              ),
            ),
        ],
      );
    }

    return const Center(child: Text('Waiting for map data...'));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async { // might work?
        if (didPop) return;
        final shouldLeave = await _confirmLeave();
        if (shouldLeave && context.mounted) {
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      },
      child: LobbyLayout(
      title: _gameStarted
          ? '${isHost ? "Host" : "Player"}: ${_myRole == 'chaser' ? 'Chaser' : 'Runner'}'
          : _gameId != null
              ? 'Lobby: $_gameId'
              : 'Connecting...',
        isConnected: _status == 'Connected',
        players: _players,
        chatMessages: _chatMessages,
        currentPlayerId: _socket?.currentPlayerId,
        playerColourMap: _playerColourMap,
        onSendChat: (text) => _socket?.sendChat(text, channel: _activeChannel),
        gameTabBuilder: _buildGameTab,
        mapTabBuilder: (isHost || _gameStarted) ? _buildMapTab : null, // host gets map tab in lobby
        banner: _buildGraceBanner(),
        gameStarted: _gameStarted,
        myRole: _myRole,
        activeChannel: _activeChannel,
        onChannelChanged: (channel) => setState(() => _activeChannel = channel),
      ),
    );
  }
}

// --- Caught Button Widget ---

class _CaughtButton extends StatefulWidget {
  const _CaughtButton({required this.onCaught, this.enabled = true});
  final VoidCallback onCaught;
  final bool enabled;

  @override
  State<_CaughtButton> createState() => _CaughtButtonState();
}

class _CaughtButtonState extends State<_CaughtButton>
    with SingleTickerProviderStateMixin {
  static const _holdDuration = Duration(seconds: 4);
  late final AnimationController _controller;
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _holdDuration);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_triggered) {
        _triggered = true;
        widget.onCaught();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDown(PointerDownEvent _) {
    if (!widget.enabled) return;
    _controller.forward(from: 0);
  }

  void _onUp(PointerEvent _) {
    if (!_triggered) {
      _controller.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dimmed = !widget.enabled;

    return Listener(
      onPointerDown: _onDown,
      onPointerUp: _onUp,
      onPointerCancel: _onUp,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Opacity(
            opacity: dimmed ? 0.4 : 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      value: _controller.value,
                      strokeWidth: 3,
                      color: Theme.of(context).colorScheme.error,
                      backgroundColor: Theme.of(context).colorScheme.error.withValues(alpha: 0.2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "I've been caught (hold)",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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